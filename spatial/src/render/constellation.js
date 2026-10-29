// The spatial constellation: root → hubs → conversations → shared tags.
// Deterministic layout comes from the same algorithm as the macOS app's
// GraphLayout3D. Nodes are instanced so a 420-thread library stays cheap.

import * as THREE from 'three';
import { anchors3D } from '../data/layout3d.js';
import { focusPath, nodeColor } from '../data/graph.js';
import { spendColor } from '../theme.js';
import { makeLabelSprite, sizeLabelSprite, disposeLabel } from './labels.js';
import { clamp } from '../util.js';

const TAG_LABEL_LIMIT = 18;
const DIM = 0.12;

const DUMMY = new THREE.Object3D();

export class Constellation {
  constructor(scene) {
    this.scene = scene;
    this.group = new THREE.Group();
    this.group.name = 'constellation';
    scene.add(this.group);

    this.nodesGroup = new THREE.Group();
    this.nodesGroup.name = 'nodes';
    this.edgesGroup = new THREE.Group();
    this.edgesGroup.name = 'edges';
    this.labelsGroup = new THREE.Group();
    this.labelsGroup.name = 'labels';
    this.overlayGroup = new THREE.Group();
    this.overlayGroup.name = 'overlay';
    this.group.add(this.nodesGroup, this.edgesGroup, this.labelsGroup, this.overlayGroup);

    this.graph = null;
    this.anchors = new Map();
    this.radii = new Map();
    this.labels = new Map();
    this.groupVisuals = new Map();
    this.raycastTargets = [];

    this.threadMesh = null;
    this.threadHit = null;
    this.threadNodes = [];
    this.tagMesh = null;
    this.tagHit = null;
    this.tagNodes = [];
    this.edgeMaterials = [];
    this.rootVisuals = null;

    this.showLabels = true;
    this.showSpend = false;
    this.focusNodeId = null;
    this.hoverNodeId = null;
    this.maxCosts = { thread: 0, group: 0 };

    this.hoverSprite = null;
    this.hoverSpriteID = null;
    this.selectionSprite = null;
    this.selectionSpriteID = null;
    this.focusEdges = null;
    this._camPos = new THREE.Vector3();
    this._labelPos = new THREE.Vector3();
    this._worldScale = new THREE.Vector3();

    this._buildOverlays();
  }

  // ------------------------------------------------------------- lifecycle

  _buildOverlays() {
    this.selectionRing = new THREE.Mesh(
      new THREE.RingGeometry(1, 1.16, 48),
      new THREE.MeshBasicMaterial({
        color: 0x5fe3ff,
        transparent: true,
        opacity: 0.9,
        side: THREE.DoubleSide,
        depthTest: false,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      }),
    );
    this.selectionRing.visible = false;
    this.selectionRing.renderOrder = 20;
    this.overlayGroup.add(this.selectionRing);
  }

  disposeGraph() {
    const disposeObject = (object) => {
      object.traverse((child) => {
        child.geometry?.dispose?.();
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        for (const material of materials) {
          material?.map?.dispose?.();
          material?.dispose?.();
        }
      });
      object.removeFromParent();
    };

    for (const child of [...this.nodesGroup.children]) disposeObject(child);
    for (const child of [...this.edgesGroup.children]) disposeObject(child);
    for (const child of [...this.labelsGroup.children]) disposeObject(child);
    if (this.focusEdges) {
      this.focusEdges.geometry.dispose();
      this.focusEdges.material.dispose();
      this.focusEdges.removeFromParent();
      this.focusEdges = null;
    }
    disposeLabel(this.hoverSprite);
    disposeLabel(this.selectionSprite);
    this.hoverSprite = null;
    this.selectionSprite = null;
    this.hoverSpriteID = null;
    this.selectionSpriteID = null;

    this.anchors.clear();
    this.radii.clear();
    this.labels.clear();
    this.groupVisuals.clear();
    this.raycastTargets = [];
    this.threadMesh = null;
    this.threadHit = null;
    this.threadNodes = [];
    this.tagMesh = null;
    this.tagHit = null;
    this.tagNodes = [];
    this.edgeMaterials = [];
    this.rootVisuals = null;

    this.selectionRing.visible = false;
    this.graph = null;
  }

  build(graph) {
    this.disposeGraph();
    this.graph = graph;
    this.anchors = anchors3D(graph);
    this.focusNodeId = null;
    this.hoverNodeId = null;
    this.hoverSpriteID = null;
    this.selectionSpriteID = null;

    this.maxCosts.group = Math.max(0, ...graph.nodes.filter((node) => node.kind === 'group').map((node) => node.cost));
    this.maxCosts.thread = Math.max(0, ...graph.nodes.filter((node) => node.kind === 'thread').map((node) => node.cost));

    this._buildRoot(graph.nodes.find((node) => node.kind === 'root'));
    this._buildGroups(graph.nodes.filter((node) => node.kind === 'group'));
    this._buildThreads(graph.nodes.filter((node) => node.kind === 'thread'));
    this._buildTags(graph.nodes.filter((node) => node.kind === 'tag'));
    this._buildEdges(graph);

    this.labelsGroup.visible = this.showLabels;
    this.applyColors();
    return this;
  }

  // ---------------------------------------------------------------- pieces

  _nodeRadius(node) {
    if (node.kind === 'root') return 18;
    if (node.kind === 'group') return 9 + Math.sqrt(Math.max(1, node.threadIDs?.length ?? node.weight)) * 1.25;
    if (node.kind === 'thread') return 3.6 + Math.max(1, node.weight) * 1.15;
    return 3.2 + Math.min(3.4, Math.sqrt(Math.max(1, node.weight)) * 1.35);
  }

  _baseColor(node) {
    if (this.showSpend) {
      if (node.kind === 'thread') {
        if (!node.cost) return new THREE.Color('#2A3446');
        return new THREE.Color(spendColor(node.cost / Math.max(0.0001, this.maxCosts.thread)));
      }
      if (node.kind === 'group') {
        if (!node.cost) return new THREE.Color('#2A3446');
        return new THREE.Color(spendColor(node.cost / Math.max(0.0001, this.maxCosts.group)));
      }
    }
    return new THREE.Color(nodeColor(node));
  }

  _buildRoot(node) {
    if (!node) return;
    const position = this.anchors.get(node.id) ?? new THREE.Vector3();
    const radius = this._nodeRadius(node);
    this.radii.set(node.id, radius);

    const group = new THREE.Group();
    group.position.copy(position);

    const core = new THREE.Mesh(
      new THREE.IcosahedronGeometry(radius * 0.42, 1),
      new THREE.MeshBasicMaterial({ color: 0xe9f1ff, transparent: true, opacity: 0.95 }),
    );
    const wire = new THREE.Mesh(
      new THREE.IcosahedronGeometry(radius, 0),
      new THREE.MeshBasicMaterial({ color: 0x5fe3ff, wireframe: true, transparent: true, opacity: 0.45 }),
    );
    const ringGeometry = new THREE.RingGeometry(radius * 1.28, radius * 1.4, 6);
    const ringMaterial = new THREE.MeshBasicMaterial({
      color: 0x5fe3ff,
      transparent: true,
      opacity: 0.35,
      side: THREE.DoubleSide,
      depthWrite: false,
    });
    const ringA = new THREE.Mesh(ringGeometry, ringMaterial);
    ringA.rotation.x = -Math.PI / 2;
    const ringB = new THREE.Mesh(ringGeometry, ringMaterial);
    group.add(core, wire, ringA, ringB);

    const hit = new THREE.Mesh(
      new THREE.SphereGeometry(1, 8, 6),
      new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false }),
    );
    hit.scale.setScalar(radius * 1.4);
    hit.userData.node = node;
    group.add(hit);
    this.raycastTargets.push(hit);

    this.rootVisuals = { group, core, wire, ringMaterial, baseOpacity: { core: 0.95, wire: 0.45, ring: 0.35 } };
    this.nodesGroup.add(group);

    const label = makeLabelSprite({
      title: node.label,
      subtitle: node.subtitle,
      color: '#E9F1FF',
      subtitleColor: '#71809A',
    });
    sizeLabelSprite(label, 12);
    label.userData.factor = 0.028;
    label.userData.priority = 100;
    // Under the root keeps the hub labels and tag cloud clear.
    label.position.copy(position).add(new THREE.Vector3(0, -radius * 2.1, 0));
    this.labelsGroup.add(label);
    this.labels.set(node.id, label);
  }

  _buildGroups(nodes) {
    for (const node of nodes) {
      const position = this.anchors.get(node.id);
      if (!position) continue;
      const radius = this._nodeRadius(node);
      this.radii.set(node.id, radius);

      const color = nodeColor(node);
      const group = new THREE.Group();
      group.position.copy(position);

      const shell = new THREE.Mesh(
        new THREE.IcosahedronGeometry(radius, 1),
        new THREE.MeshBasicMaterial({ color, wireframe: true, transparent: true, opacity: 0.42 }),
      );
      const outer = new THREE.Mesh(
        new THREE.IcosahedronGeometry(radius * 1.3, 0),
        new THREE.MeshBasicMaterial({ color, wireframe: true, transparent: true, opacity: 0.14 }),
      );
      const core = new THREE.Mesh(
        new THREE.IcosahedronGeometry(radius * 0.28, 1),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9 }),
      );
      group.add(shell, outer, core);

      const hit = new THREE.Mesh(
        new THREE.SphereGeometry(1, 8, 6),
        new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false }),
      );
      hit.scale.setScalar(Math.max(radius * 1.3, 22));
      hit.userData.node = node;
      group.add(hit);
      this.raycastTargets.push(hit);

      this.nodesGroup.add(group);
      this.groupVisuals.set(node.id, {
        group,
        materials: [
          { material: shell.material, base: 0.42 },
          { material: outer.material, base: 0.14 },
          { material: core.material, base: 0.9 },
        ],
        color,
      });

      const label = makeLabelSprite({
        title: node.label,
        subtitle: node.subtitle,
        color,
        subtitleColor: '#71809A',
      });
      sizeLabelSprite(label, 11.5);
      label.userData.factor = 0.024;
      label.userData.priority = 50;
      label.position.copy(position).add(new THREE.Vector3(0, radius * 1.7 + 8, 0));
      this.labelsGroup.add(label);
      this.labels.set(node.id, label);
    }
  }

  _buildThreads(nodes) {
    if (!nodes.length) return;
    this.threadNodes = nodes;

    const geometry = new THREE.IcosahedronGeometry(1, 0);
    const material = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: 0.96,
      fog: true,
    });
    const mesh = new THREE.InstancedMesh(geometry, material, nodes.length);
    mesh.frustumCulled = false;
    mesh.userData.nodes = nodes;
    mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);

    nodes.forEach((node, index) => {
      const position = this.anchors.get(node.id) ?? new THREE.Vector3();
      const radius = this._nodeRadius(node);
      this.radii.set(node.id, radius);
      DUMMY.position.copy(position);
      DUMMY.scale.setScalar(radius);
      DUMMY.updateMatrix();
      mesh.setMatrixAt(index, DUMMY.matrix);
      mesh.setColorAt(index, new THREE.Color(nodeColor(node)));
    });
    mesh.instanceMatrix.needsUpdate = true;
    mesh.instanceColor.needsUpdate = true;
    this.nodesGroup.add(mesh);
    this.threadMesh = mesh;

    const hitGeometry = new THREE.SphereGeometry(1, 6, 4);
    const hitMaterial = new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false });
    const hit = new THREE.InstancedMesh(hitGeometry, hitMaterial, nodes.length);
    hit.frustumCulled = false;
    hit.userData.nodes = nodes;
    nodes.forEach((node, index) => {
      const position = this.anchors.get(node.id) ?? new THREE.Vector3();
      DUMMY.position.copy(position);
      DUMMY.scale.setScalar(Math.max(13, this._nodeRadius(node) * 1.8));
      DUMMY.updateMatrix();
      hit.setMatrixAt(index, DUMMY.matrix);
    });
    hit.instanceMatrix.needsUpdate = true;
    this.nodesGroup.add(hit);
    this.threadHit = hit;
    this.raycastTargets.push(hit);
  }

  _buildTags(nodes) {
    if (!nodes.length) return;
    this.tagNodes = nodes;

    const mesh = new THREE.InstancedMesh(
      new THREE.OctahedronGeometry(1, 0),
      new THREE.MeshBasicMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0.9,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        fog: false,
      }),
      nodes.length,
    );
    mesh.frustumCulled = false;
    mesh.userData.nodes = nodes;

    nodes.forEach((node, index) => {
      const position = this.anchors.get(node.id) ?? new THREE.Vector3();
      const radius = this._nodeRadius(node);
      this.radii.set(node.id, radius);
      DUMMY.position.copy(position);
      DUMMY.scale.setScalar(radius);
      DUMMY.rotation.set(0.4, 0.7, 0.2);
      DUMMY.updateMatrix();
      mesh.setMatrixAt(index, DUMMY.matrix);
      mesh.setColorAt(index, new THREE.Color(nodeColor(node)));
    });
    mesh.instanceMatrix.needsUpdate = true;
    mesh.instanceColor.needsUpdate = true;
    this.nodesGroup.add(mesh);
    this.tagMesh = mesh;

    const hit = new THREE.InstancedMesh(
      new THREE.SphereGeometry(1, 6, 4),
      new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false }),
      nodes.length,
    );
    hit.frustumCulled = false;
    hit.userData.nodes = nodes;
    nodes.forEach((node, index) => {
      const position = this.anchors.get(node.id) ?? new THREE.Vector3();
      DUMMY.position.copy(position);
      DUMMY.rotation.set(0, 0, 0);
      DUMMY.scale.setScalar(Math.max(12, this._nodeRadius(node) * 1.9));
      DUMMY.updateMatrix();
      hit.setMatrixAt(index, DUMMY.matrix);
    });
    hit.instanceMatrix.needsUpdate = true;
    this.nodesGroup.add(hit);
    this.tagHit = hit;
    this.raycastTargets.push(hit);

    // A restrained set of tag words keeps the space legible.
    const labelled = [...nodes]
      .sort((a, b) => (b.weight ?? 0) - (a.weight ?? 0))
      .slice(0, TAG_LABEL_LIMIT);
    for (const node of labelled) {
      const position = this.anchors.get(node.id);
      if (!position) continue;
      const color = nodeColor(node);
      const label = makeLabelSprite({ title: node.label, color, subtitleColor: '#71809A' });
      sizeLabelSprite(label, 7.2);
      label.userData.factor = 0.018;
      label.userData.priority = 10 + (node.weight ?? 1);
      label.position.copy(position).add(new THREE.Vector3(0, this._nodeRadius(node) + 5, 0));
      label.material.opacity = 0.72;
      this.labelsGroup.add(label);
      this.labels.set(node.id, label);
    }
  }

  _buildEdges(graph) {
    const buckets = { strong: [], mid: [], faint: [] };
    const nodeByID = new Map(graph.nodes.map((node) => [node.id, node]));

    for (const edge of graph.edges) {
      const from = this.anchors.get(edge.source);
      const to = this.anchors.get(edge.target);
      if (!from || !to) continue;
      const target = nodeByID.get(edge.target);
      let color;
      if (edge.kind === 'threadTag') {
        color = '#5FE3FF';
      } else if (edge.kind === 'rootGroup') {
        color = nodeColor(nodeByID.get(edge.target) ?? { kind: 'group', colorSeed: 0 });
      } else {
        color = nodeColor(target ?? { kind: 'thread', provider: 'other' });
      }
      const bucket = edge.kind === 'threadTag' ? 'faint' : edge.kind === 'rootGroup' ? 'strong' : 'mid';
      buckets[bucket].push({ from, to, color });
    }

    const specs = [
      { key: 'strong', opacity: 0.5, width: 1 },
      { key: 'mid', opacity: 0.34, width: 1 },
      { key: 'faint', opacity: 0.17, width: 1 },
    ];

    for (const spec of specs) {
      const entries = buckets[spec.key];
      if (!entries.length) continue;
      const positions = new Float32Array(entries.length * 6);
      const colors = new Float32Array(entries.length * 6);
      const scratch = new THREE.Color();
      entries.forEach((entry, index) => {
        positions.set([entry.from.x, entry.from.y, entry.from.z, entry.to.x, entry.to.y, entry.to.z], index * 6);
        scratch.set(entry.color);
        colors.set([scratch.r, scratch.g, scratch.b, scratch.r, scratch.g, scratch.b], index * 6);
      });
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
      const material = new THREE.LineBasicMaterial({
        vertexColors: true,
        transparent: true,
        opacity: spec.opacity,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        fog: false,
      });
      material.userData.baseOpacity = spec.opacity;
      const lines = new THREE.LineSegments(geometry, material);
      lines.renderOrder = 1;
      this.edgesGroup.add(lines);
      this.edgeMaterials.push(material);
    }
  }

  // ---------------------------------------------------------------- colors

  /** Applies spend/base colors plus the current focus dimming. */
  applyColors() {
    if (!this.graph) return;
    const path = this.focusNodeId ? focusPath(this.graph, this.focusNodeId) : null;

    const applyInstances = (mesh, nodes) => {
      if (!mesh) return;
      nodes.forEach((node, index) => {
        const base = this._baseColor(node);
        const color = path && !path.has(node.id) ? base.clone().multiplyScalar(DIM) : base;
        mesh.setColorAt(index, color);
      });
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    };

    applyInstances(this.threadMesh, this.threadNodes);
    applyInstances(this.tagMesh, this.tagNodes);

    for (const [id, visuals] of this.groupVisuals) {
      const inPath = !path || path.has(id);
      for (const entry of visuals.materials) {
        entry.material.opacity = inPath ? entry.base : entry.base * DIM;
      }
    }

    if (this.rootVisuals) {
      const { core, wire, ringMaterial, baseOpacity } = this.rootVisuals;
      const inPath = !path || path.has('root');
      core.material.opacity = inPath ? baseOpacity.core : baseOpacity.core * DIM;
      wire.material.opacity = inPath ? baseOpacity.wire : baseOpacity.wire * DIM;
      ringMaterial.opacity = inPath ? baseOpacity.ring : baseOpacity.ring * DIM;
    }

    for (const material of this.edgeMaterials) {
      material.opacity = path ? material.userData.baseOpacity * 0.3 : material.userData.baseOpacity;
    }

    for (const [id, label] of this.labels) {
      label.material.opacity = !path || path.has(id) ? (id.startsWith('tag:') ? 0.72 : 1) : 0.18;
    }

    this._rebuildFocusEdges(path);
    this._updateSelection();
  }

  _rebuildFocusEdges(path) {
    if (this.focusEdges) {
      this.focusEdges.geometry.dispose();
      this.focusEdges.material.dispose();
      this.focusEdges.removeFromParent();
      this.focusEdges = null;
    }
    if (!path || !this.graph) return;

    const entries = [];
    for (const edge of this.graph.edges) {
      if (!path.has(edge.source) || !path.has(edge.target)) continue;
      const from = this.anchors.get(edge.source);
      const to = this.anchors.get(edge.target);
      if (!from || !to) continue;
      entries.push([from, to]);
    }
    if (!entries.length) return;

    const positions = new Float32Array(entries.length * 6);
    entries.forEach(([from, to], index) => {
      positions.set([from.x, from.y, from.z, to.x, to.y, to.z], index * 6);
    });
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const material = new THREE.LineBasicMaterial({
      color: 0x5fe3ff,
      transparent: true,
      opacity: 0.8,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      fog: false,
    });
    this.focusEdges = new THREE.LineSegments(geometry, material);
    this.focusEdges.renderOrder = 2;
    this.overlayGroup.add(this.focusEdges);
  }

  // --------------------------------------------------------------- focus

  setFocus(nodeID) {
    this.focusNodeId = nodeID;
    this.applyColors();
  }

  setHover(nodeID) {
    if (nodeID === this.hoverNodeId) return;
    this.hoverNodeId = nodeID;
    this._updateHover();
  }

  setLabels(visible) {
    this.showLabels = visible;
    this.labelsGroup.visible = visible;
  }

  setSpend(enabled) {
    this.showSpend = enabled;
    this.applyColors();
  }

  // -------------------------------------------------------------- picking

  pick(raycaster) {
    const hits = raycaster.intersectObjects(this.raycastTargets, false);
    if (!hits.length) return null;
    const hit = hits[0];
    const node = hit.object.userData.node ?? hit.object.userData.nodes?.[hit.instanceId];
    if (!node) return null;
    return { node, point: hit.point, distance: hit.distance };
  }

  nodeWorldPosition(nodeID) {
    const anchor = this.anchors.get(nodeID);
    if (!anchor) return null;
    return anchor.clone().applyMatrix4(this.group.matrixWorld);
  }

  // --------------------------------------------------------------- labels

  _makeNodeSprite(node) {
    const radius = this.radii.get(node.id) ?? 8;
    const isTag = node.kind === 'tag';
    const sprite = makeLabelSprite({
      title: isTag ? node.label : node.label,
      subtitle: isTag ? null : node.subtitle ?? '',
      color: isTag ? nodeColor(node) : '#E9F1FF',
      subtitleColor: '#71809A',
    });
    sizeLabelSprite(sprite, isTag ? 8 : 10);
    sprite.userData.factor = isTag ? 0.018 : 0.021;
    sprite.userData.priority = 900;
    const anchor = this.anchors.get(node.id);
    if (anchor) sprite.position.copy(anchor).add(new THREE.Vector3(0, radius + 7, 0));
    sprite.material.opacity = 0.95;
    this.overlayGroup.add(sprite);
    return sprite;
  }

  _updateHover() {
    if (this.hoverSprite && this.hoverSpriteID !== this.focusNodeId) {
      disposeLabel(this.hoverSprite);
      this.hoverSprite = null;
    }
    this.hoverSpriteID = this.hoverNodeId;
    if (!this.hoverNodeId || this.hoverNodeId === this.focusNodeId) return;
    if (this.labels.has(this.hoverNodeId)) return;
    const node = this.graph?.nodes.find((item) => item.id === this.hoverNodeId);
    if (!node) return;
    this.hoverSprite = this._makeNodeSprite(node);
  }

  _updateSelection() {
    const node = this.graph?.nodes.find((item) => item.id === this.focusNodeId);
    if (!node) {
      this.selectionRing.visible = false;
      if (this.selectionSprite) {
        disposeLabel(this.selectionSprite);
        this.selectionSprite = null;
        this.selectionSpriteID = null;
      }
      return;
    }
    const anchor = this.anchors.get(node.id);
    const radius = this.radii.get(node.id) ?? 8;
    if (!anchor) return;

    this.selectionRing.visible = true;
    this.selectionRing.position.copy(anchor);
    this.selectionRing.scale.setScalar(radius * 2.4);
    this.selectionRing.userData.baseScale = radius * 2.4;
    this.selectionRing.material.color.set(nodeColor(node));

    if (this.selectionSpriteID !== node.id) {
      if (this.selectionSprite) disposeLabel(this.selectionSprite);
      this.selectionSprite = null;
      this.selectionSpriteID = node.id;
      if (!this.labels.has(node.id)) {
        this.selectionSprite = this._makeNodeSprite(node);
      }
    }
  }

  // ---------------------------------------------------------------- frame

  update(dt, camera) {
    const time = performance.now() / 1000;

    if (this.selectionRing.visible) {
      this.selectionRing.quaternion.copy(camera.quaternion);
      const base = this.selectionRing.userData.baseScale ?? 10;
      this.selectionRing.scale.setScalar(base * (1 + 0.06 * Math.sin(time * 3)));
      this.selectionRing.material.opacity = 0.7 + 0.2 * Math.sin(time * 3);
    }

    if (this.focusEdges) {
      this.focusEdges.material.opacity = 0.68 + 0.16 * Math.sin(time * 2.2);
    }

    if (this.tagMesh) {
      // Slow crystalline drift; the layout itself stays deterministic.
      this.tagMesh.rotation.y = Math.sin(time * 0.25) * 0.03;
    }

    this._updateLabelScale(camera);
  }

  /**
   * Sprites are sized in layout units, but legibility in a headset depends on
   * angular size. Scale each label with camera distance and drop labels that
   * would overlap a stronger one, so the cloud stays readable from any angle.
   */
  _updateLabelScale(camera) {
    if (!this.labelsGroup.visible && !this.selectionSprite && !this.hoverSprite) return;
    camera.getWorldPosition(this._camPos);
    camera.updateMatrixWorld();
    this.group.getWorldScale(this._worldScale);
    const worldScale = Math.max(0.0001, this._worldScale.x);

    const right = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 0);
    const up = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 1);
    const forward = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 2).negate();

    const measure = (sprite) => {
      if (!sprite) return null;
      sprite.getWorldPosition(this._labelPos);
      const dir = this._labelPos.clone().sub(this._camPos);
      const distance = dir.length();
      if (distance < 0.05) return null;
      const worldHeight = clamp(distance * (sprite.userData.factor ?? 0.02), 0.022, 0.2);
      const height = worldHeight / worldScale;
      sprite.scale.set(height * (sprite.userData.aspect ?? 4), height, 1);
      return { sprite, dir, distance, worldHeight };
    };

    const toScreen = (entry) => {
      const inv = 1 / Math.max(0.05, entry.distance);
      return {
        x: entry.dir.dot(right) * inv,
        y: entry.dir.dot(up) * inv,
        halfW: entry.worldHeight * (entry.sprite.userData.aspect ?? 4) * 0.5 * inv,
        halfH: entry.worldHeight * 0.5 * inv,
        ahead: entry.dir.dot(forward) * inv > 0.05,
      };
    };

    const candidates = [];
    for (const sprite of this.labels.values()) {
      const entry = measure(sprite);
      if (!entry) continue;
      candidates.push(entry);
    }
    candidates.sort((a, b) => (b.sprite.userData.priority ?? 0) - (a.sprite.userData.priority ?? 0));

    const placed = [];
    for (const entry of candidates) {
      const screen = toScreen(entry);
      if (!screen.ahead) {
        entry.sprite.visible = false;
        continue;
      }
      const margin = 0.0025;
      const overlaps = placed.some(
        (other) =>
          Math.abs(screen.x - other.x) < screen.halfW + other.halfW + margin &&
          Math.abs(screen.y - other.y) < screen.halfH + other.halfH + margin,
      );
      entry.sprite.visible = !overlaps;
      if (!overlaps) placed.push(screen);
    }

    const overlay = [this.selectionSprite, this.hoverSprite];
    for (const sprite of overlay) {
      const entry = measure(sprite);
      if (!entry) continue;
      sprite.visible = toScreen(entry).ahead;
    }
  }
}
