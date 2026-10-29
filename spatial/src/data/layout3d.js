// Port of MindMap/Core/Sources/MindMapCore/Graph/GraphLayout3D.swift.
// Deterministic anchors: groups on a Fibonacci sphere, conversations in a
// cloud around their hub, shared tags floating between the threads they link.

import * as THREE from 'three';
import { hash32 } from '../util.js';

function fibonacciDirection(index, count) {
  const n = Math.max(1, count);
  const y = 1 - (2 * (index + 0.5)) / n;
  const radius = Math.sqrt(Math.max(0, 1 - y * y));
  const theta = index * 2.399963229728653; // golden angle
  return new THREE.Vector3(radius * Math.cos(theta), y, radius * Math.sin(theta)).normalize();
}

function jitter(id, minimum, maximum) {
  const unit = (hash32(id) % 10_000) / 10_000;
  return minimum + (maximum - minimum) * unit;
}

function placeFlat(groups, threads, hubRadius, anchors) {
  groups.forEach((group, index) => {
    const direction = fibonacciDirection(index, groups.length);
    const hub = direction.clone().multiplyScalar(hubRadius);
    anchors.set(group.id, hub);

    const children = threads
      .filter((node) => node.groupID === group.id)
      .sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true }));
    const count = Math.max(1, children.length);
    const cloudRadius = 100 + 9 * Math.sqrt(count);
    const outward = hub.clone().normalize();
    const minRadius = hubRadius * 0.42;

    children.forEach((node, childIndex) => {
      const childDirection = fibonacciDirection(childIndex, count);
      const point = hub
        .clone()
        .add(childDirection.multiplyScalar(cloudRadius * jitter(node.id, 0.78, 1.24)))
        .add(outward.clone().multiplyScalar(18));
      if (point.length() < minRadius) point.normalize().multiplyScalar(minRadius);
      anchors.set(node.id, point);
    });
  });
}

function placeTags(graph, hubRadius, anchors) {
  const neighbors = new Map();
  for (const edge of graph.edges) {
    if (!neighbors.has(edge.source)) neighbors.set(edge.source, []);
    if (!neighbors.has(edge.target)) neighbors.set(edge.target, []);
    neighbors.get(edge.source).push(edge.target);
    neighbors.get(edge.target).push(edge.source);
  }

  for (const tag of graph.nodes.filter((node) => node.kind === 'tag')) {
    const connected = (neighbors.get(tag.id) ?? []).map((id) => anchors.get(id)).filter(Boolean);
    if (!connected.length) {
      const direction = fibonacciDirection(hash32(tag.id) % 997, 997);
      anchors.set(tag.id, direction.multiplyScalar(hubRadius * 0.8));
      continue;
    }
    const average = connected.reduce((sum, point) => sum.add(point), new THREE.Vector3()).divideScalar(connected.length);
    const direction = fibonacciDirection(hash32(tag.id) % 991, 991);
    average.add(direction.multiplyScalar(26));
    if (average.length() < hubRadius * 0.38) {
      average.normalize().multiplyScalar(hubRadius * 0.38);
    }
    anchors.set(tag.id, average);
  }
}

export function anchors3D(graph) {
  const anchors = new Map([['root', new THREE.Vector3()]]);
  const groups = graph.nodes.filter((node) => node.kind === 'group');
  if (!groups.length) return anchors;

  const threads = graph.nodes.filter((node) => node.kind === 'thread');
  const totalThreads = Math.max(1, threads.length);
  const hubRadius = 330 + 7 * Math.sqrt(totalThreads);

  placeFlat(groups, threads, hubRadius, anchors);
  placeTags(graph, hubRadius, anchors);
  return anchors;
}

export function graphBounds(graph, anchors) {
  const box = new THREE.Box3();
  let count = 0;
  for (const node of graph.nodes) {
    const point = anchors.get(node.id);
    if (!point) continue;
    box.expandByPoint(point);
    count += 1;
  }
  if (!count) box.setFromCenterAndSize(new THREE.Vector3(), new THREE.Vector3(100, 100, 100));
  return box;
}
