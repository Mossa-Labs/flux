/**
 * Converts between Pipeline IR (JSON) and React Flow nodes/edges.
 */

import { type Node, type Edge, MarkerType } from '@xyflow/react';
import type {
  PipelineIR,
  StepIR,
  IRNode,
  IREdge,
  SinkConfig,
  StepNodeData,
  SourceNodeData,
  SinkNodeData,
} from './types';

const NODE_VERTICAL_SPACING = 120;
const NODE_START_Y = 50;
const NODE_CENTER_X = 250;

/**
 * Convert Pipeline IR to React Flow nodes and edges
 */
export function irToFlow(
  ir: PipelineIR,
  sourceQueue?: string,
  sinks: SinkConfig[] = []
): { nodes: Node[]; edges: Edge[] } {
  const nodes: Node[] = [];
  const edges: Edge[] = [];

  const hasIRNodes = ir.nodes && ir.nodes.length > 0;
  const hasIREdges = ir.edges && ir.edges.length > 0;

  // Load or generate source/sink nodes
  if (hasIRNodes) {
    for (const irNode of ir.nodes!) {
      if (irNode.type === 'source') {
        nodes.push({
          id: irNode.id,
          type: 'source',
          position: irNode.position,
          data: {
            label: irNode.label,
            queue: irNode.sourceConfig?.queue,
            sourceType: irNode.sourceConfig?.type || 'queue',
            sourceConfig: irNode.sourceConfig,
          } as SourceNodeData,
        });
      } else if (irNode.type === 'sink') {
        nodes.push({
          id: irNode.id,
          type: 'sink',
          position: irNode.position,
          data: {
            label: irNode.label,
            sinkType: irNode.sinkType || 'queue',
            sinkId: irNode.sinkId,
            sinkName: irNode.sinkName,
            queue: irNode.queue,
          } as SinkNodeData,
        });
      }
    }
  } else {
    // Backward compatibility: generate default source/sink
    nodes.push({
      id: 'source',
      type: 'source',
      position: { x: NODE_CENTER_X, y: NODE_START_Y },
      data: {
        label: 'Source',
        queue: sourceQueue || 'events.incoming',
        sourceType: 'queue',
        sourceConfig: {
          type: 'queue',
          queue: sourceQueue || 'events.incoming',
          prefetchCount: 10,
          ackMode: 'auto',
        },
      } as SourceNodeData,
    });
  }

  // Add step nodes
  let yPosition = NODE_START_Y + NODE_VERTICAL_SPACING;
  const steps = ir.steps || [];
  for (const step of steps) {
    const nodeId = step.id || `step-${nodes.length}`;

    const config =
      step.type === 'script'
        ? { code: step.code || '', timeout_ms: step.timeout_ms || 5000 }
        : step.config || {};

    nodes.push({
      id: nodeId,
      type: 'step',
      position: { x: NODE_CENTER_X, y: yPosition },
      data: {
        label: getStepLabel(step),
        stepType: getStepType(step),
        config,
      } as StepNodeData,
    });

    yPosition += NODE_VERTICAL_SPACING;
  }

  // Add default output node if no IR nodes were provided
  if (!hasIRNodes) {
    nodes.push({
      id: 'output',
      type: 'sink',
      position: { x: NODE_CENTER_X, y: yPosition },
      data: {
        label: 'Output',
        sinkType: 'queue',
      } as SinkNodeData,
    });
  }

  // Load or generate edges
  if (hasIREdges) {
    for (const irEdge of ir.edges!) {
      edges.push({
        id: irEdge.id,
        source: irEdge.source,
        target: irEdge.target,
        type: 'smoothstep',
        label: irEdge.label || undefined,
        markerEnd: { type: MarkerType.ArrowClosed, width: 20, height: 20 },
      });
    }
  } else {
    // Backward compatibility: generate linear edges
    const sortedNodes = [...nodes].sort((a, b) => a.position.y - b.position.y);
    for (let i = 0; i < sortedNodes.length - 1; i++) {
      edges.push({
        id: `${sortedNodes[i].id}-${sortedNodes[i + 1].id}`,
        source: sortedNodes[i].id,
        target: sortedNodes[i + 1].id,
        type: 'smoothstep',
        markerEnd: { type: MarkerType.ArrowClosed, width: 20, height: 20 },
      });
    }
  }

  return { nodes, edges };
}

/**
 * Convert React Flow nodes back to Pipeline IR
 */
export function flowToIR(nodes: Node[], edges: Edge[]): PipelineIR {
  const steps: StepIR[] = [];
  const irNodes: IRNode[] = [];
  const irEdges: IREdge[] = [];

  // Extract step nodes in topological order
  const orderedNodeIds = getOrderedNodeIds(nodes, edges);

  for (const nodeId of orderedNodeIds) {
    const node = nodes.find((n) => n.id === nodeId);
    if (!node || node.type !== 'step') continue;

    const data = node.data as StepNodeData;
    const config = data.config || {};

    if (data.stepType === 'script') {
      steps.push({
        id: nodeId,
        type: 'script',
        language: 'lua',
        code: (config.code as string) || '',
        timeout_ms: (config.timeout_ms as number) || 5000,
      });
    } else if (data.stepType === 'anomaly') {
      steps.push({
        id: nodeId,
        type: 'ai',
        operation: 'anomaly_detect',
        config,
      });
    } else {
      steps.push({
        id: nodeId,
        type: 'native',
        operation: data.stepType,
        config,
      });
    }
  }

  // Extract source and sink nodes
  for (const node of nodes) {
    if (node.type === 'source') {
      const data = node.data as SourceNodeData;
      irNodes.push({
        id: node.id,
        type: 'source',
        label: data.label || 'Source',
        position: node.position,
        sourceConfig: data.sourceConfig || {
          type: data.sourceType || 'queue',
          queue: data.queue,
        },
      });
    } else if (node.type === 'sink') {
      const data = node.data as SinkNodeData;
      irNodes.push({
        id: node.id,
        type: 'sink',
        label: data.label || 'Output',
        position: node.position,
        sinkType: data.sinkType,
        sinkId: data.sinkId,
        sinkName: data.sinkName,
        queue: data.queue,
      });
    }
  }

  // Extract edges
  for (const edge of edges) {
    irEdges.push({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      label: (edge.label as string) || undefined,
    });
  }

  return {
    version: '1.0',
    steps,
    nodes: irNodes,
    edges: irEdges,
  };
}

/**
 * Get ordered step node IDs using topological sort (Kahn's algorithm).
 * Supports fan-in (multiple sources) and fan-out (branching).
 */
function getOrderedNodeIds(nodes: Node[], edges: Edge[]): string[] {
  const stepNodeIds = new Set(nodes.filter((n) => n.type === 'step').map((n) => n.id));
  const sourceNodeIds = new Set(nodes.filter((n) => n.type === 'source').map((n) => n.id));
  const sinkNodeIds = new Set(nodes.filter((n) => n.type === 'sink').map((n) => n.id));

  // Build adjacency list (only for step-to-step or source-to-step edges)
  const adjacency = new Map<string, Set<string>>();
  const inDegree = new Map<string, number>();

  // Initialize in-degree for all step nodes
  for (const id of stepNodeIds) {
    inDegree.set(id, 0);
    adjacency.set(id, new Set());
  }

  for (const edge of edges) {
    const { source, target } = edge;

    // Skip edges to/from sink nodes for ordering purposes
    if (sinkNodeIds.has(target) || sinkNodeIds.has(source)) continue;

    if (sourceNodeIds.has(source) && stepNodeIds.has(target)) {
      // Source -> step: don't count as in-degree (sources are entry points)
    } else if (stepNodeIds.has(source) && stepNodeIds.has(target)) {
      // Step -> step: count in-degree
      if (!adjacency.has(source)) adjacency.set(source, new Set());
      adjacency.get(source)!.add(target);
      inDegree.set(target, (inDegree.get(target) || 0) + 1);
    }
  }

  // Also track which step nodes are reachable from source nodes
  for (const edge of edges) {
    if (sourceNodeIds.has(edge.source) && stepNodeIds.has(edge.target)) {
      // These step nodes are direct entry points after sources
    }
  }

  // Kahn's algorithm
  const queue: string[] = [];
  const ordered: string[] = [];

  // Start with step nodes that have zero in-degree
  for (const [id, degree] of inDegree) {
    if (degree === 0) {
      queue.push(id);
    }
  }

  while (queue.length > 0) {
    const nodeId = queue.shift()!;
    ordered.push(nodeId);

    const targets = adjacency.get(nodeId);
    if (targets) {
      for (const targetId of targets) {
        const newDegree = (inDegree.get(targetId) || 1) - 1;
        inDegree.set(targetId, newDegree);
        if (newDegree === 0) {
          queue.push(targetId);
        }
      }
    }
  }

  if (ordered.length < stepNodeIds.size) {
    console.warn(
      `Cycle detected in pipeline graph. ${stepNodeIds.size - ordered.length} node(s) excluded.`
    );
  }

  return ordered;
}

function getStepLabel(step: StepIR): string {
  if (step.operation) {
    const labels: Record<string, string> = {
      filter: 'Filter',
      map: 'Transform',
      rename: 'Rename',
    };
    return labels[step.operation] || step.operation;
  }
  if (step.type === 'script') return 'Script';
  if (step.type === 'ai') return 'AI Detect';
  return 'Step';
}

function getStepType(step: StepIR): StepNodeData['stepType'] {
  if (step.type === 'script') return 'script';
  if (step.type === 'ai') return 'anomaly';
  if (step.operation === 'filter') return 'filter';
  if (step.operation === 'rename') return 'rename';
  return 'map';
}

/**
 * Create a new step node at a given position
 */
export function createStepNode(
  id: string,
  stepType: StepNodeData['stepType'],
  position: { x: number; y: number }
): Node {
  const labels: Record<string, string> = {
    filter: 'Filter',
    map: 'Transform',
    rename: 'Rename',
    script: 'Script',
    anomaly: 'AI Detect',
  };

  return {
    id,
    type: 'step',
    position,
    data: {
      label: labels[stepType] || 'Step',
      stepType,
      config: {},
    } as StepNodeData,
  };
}

/**
 * Create a new sink node
 */
export function createSinkNode(
  id: string,
  sink: SinkConfig,
  position: { x: number; y: number }
): Node {
  return {
    id,
    type: 'sink',
    position,
    data: {
      label: sink.name,
      sinkId: sink.id,
      sinkType: sink.type,
      sinkName: sink.name,
    } as SinkNodeData,
  };
}

/**
 * Create a new source node
 */
export function createSourceNode(
  id: string,
  position: { x: number; y: number },
  queue?: string
): Node {
  return {
    id,
    type: 'source',
    position,
    data: {
      label: 'Source',
      queue: queue || 'events.incoming',
      sourceType: 'queue',
      sourceConfig: {
        type: 'queue',
        queue: queue || 'events.incoming',
        prefetchCount: 10,
        ackMode: 'auto',
      },
    } as SourceNodeData,
  };
}

/**
 * Create a new queue output node
 */
export function createQueueNode(
  id: string,
  position: { x: number; y: number },
  queue?: string
): Node {
  return {
    id,
    type: 'sink',
    position,
    data: {
      label: 'Queue Output',
      sinkType: 'queue',
      queue: queue || 'events.processed',
    } as SinkNodeData,
  };
}
