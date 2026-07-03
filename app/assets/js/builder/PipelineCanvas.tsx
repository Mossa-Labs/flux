import React, { useCallback, useRef, useMemo, useImperativeHandle, forwardRef } from 'react';
import {
  ReactFlow,
  Controls,
  Background,
  BackgroundVariant,
  useNodesState,
  useEdgesState,
  addEdge,
  Connection,
  Node,
  ReactFlowProvider,
  useReactFlow,
  OnSelectionChangeFunc,
  MarkerType,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

import { SourceNode, StepNode, SinkNode } from './nodes';
import { irToFlow, flowToIR, createStepNode, createSinkNode, createSourceNode, createQueueNode } from './ir-converter';
import type { BuilderProps, StepNodeData, PipelineNodeData, PipelineCanvasHandle } from './types';

// IMPORTANT: nodeTypes must be defined outside component to prevent re-renders
const nodeTypes = {
  source: SourceNode,
  step: StepNode,
  sink: SinkNode,
};

// Unique ID generator
let idCounter = 0;
const getId = () => `node_${Date.now()}_${idCounter++}`;

interface PipelineCanvasInnerProps extends BuilderProps {
  sourceQueue?: string;
}

const PipelineCanvasInner = forwardRef<PipelineCanvasHandle, PipelineCanvasInnerProps>(function PipelineCanvasInner({
  initialIR,
  availableSinks,
  sourceQueue,
  onIRChange,
  onSelectionChange,
}, ref) {
  const reactFlowWrapper = useRef<HTMLDivElement>(null);
  const { screenToFlowPosition, getNodes, getEdges } = useReactFlow();

  // Convert initial IR to nodes/edges
  const { nodes: initialNodes, edges: initialEdges } = useMemo(
    () => irToFlow(initialIR, sourceQueue, availableSinks),
    [] // Only run once on mount
  );

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);

  // Notify parent when IR changes. Read the live React Flow store (getNodes/
  // getEdges) rather than the closed-over `nodes`/`edges` so the IR we push is
  // never one mutation behind — callers schedule this via setTimeout(..., 0)
  // right after a setNodes/setEdges, by which point the store is up to date.
  const updateIR = useCallback(() => {
    const ir = flowToIR(getNodes(), getEdges());
    onIRChange(ir);
  }, [getNodes, getEdges, onIRChange]);

  // Handle new connections
  const onConnect = useCallback(
    (params: Connection) => {
      setEdges((eds) => addEdge({
        ...params,
        type: 'smoothstep',
        markerEnd: { type: MarkerType.ArrowClosed, width: 20, height: 20 },
      }, eds));
      setTimeout(updateIR, 0);
    },
    [setEdges, updateIR]
  );

  // Handle drag over for dropping new nodes
  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
  }, []);

  // Build a node of the given palette type at a flow-space position. Shared by
  // drag-and-drop (onDrop) and click-to-add (addNode); returns null for an
  // unknown type or a sink whose id can't be resolved.
  const buildNode = useCallback(
    (nodeType: string, sinkId: number | null, position: { x: number; y: number }): Node | null => {
      if (nodeType === 'source') {
        return createSourceNode(getId(), position);
      } else if (nodeType === 'queue') {
        return createQueueNode(getId(), position);
      } else if (nodeType === 'sink' && sinkId != null) {
        const sink = availableSinks.find((s) => s.id === sinkId);
        return sink ? createSinkNode(getId(), sink, position) : null;
      } else if (['filter', 'map', 'rename', 'script', 'anomaly'].includes(nodeType)) {
        return createStepNode(getId(), nodeType as StepNodeData['stepType'], position);
      }
      return null;
    },
    [availableSinks]
  );

  // Insert a freshly built node as the selected one (deselecting any others).
  // Selecting it makes React Flow fire onSelectionChange, which is what tells
  // LiveView to focus the right-hand config panel on the new node.
  const insertNode = useCallback(
    (newNode: Node) => {
      setNodes((nds) =>
        nds
          .map((n) => (n.selected ? { ...n, selected: false } : n))
          .concat({ ...newNode, selected: true })
      );
      setTimeout(updateIR, 0);
    },
    [setNodes, updateIR]
  );

  // Handle drop of new nodes
  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();

      const nodeType = event.dataTransfer.getData('application/reactflow/type');
      const sinkIdRaw = event.dataTransfer.getData('application/reactflow/sinkId');

      if (!nodeType) {
        return;
      }

      const position = screenToFlowPosition({
        x: event.clientX,
        y: event.clientY,
      });

      const newNode = buildNode(nodeType, sinkIdRaw ? parseInt(sinkIdRaw, 10) : null, position);

      if (newNode) {
        insertNode(newNode);
      }
    },
    [screenToFlowPosition, buildNode, insertNode]
  );

  // Add a node from a palette click (companion to drag-and-drop). Places it near
  // the center of the visible canvas, with a small per-node offset so repeated
  // clicks don't stack exactly on top of each other.
  const addNode = useCallback(
    (nodeType: string, sinkId?: number) => {
      const wrapper = reactFlowWrapper.current;
      const rect = wrapper?.getBoundingClientRect();
      const jitter = (idCounter % 6) * 28;

      const position = rect
        ? screenToFlowPosition({
            x: rect.left + rect.width / 2 + jitter,
            y: rect.top + rect.height / 2 + jitter,
          })
        : { x: 250 + jitter, y: 150 + jitter };

      const newNode = buildNode(nodeType, sinkId ?? null, position);

      if (newNode) {
        insertNode(newNode);
      }
    },
    [screenToFlowPosition, buildNode, insertNode]
  );

  // Handle node changes (position, selection, etc.)
  const handleNodesChange = useCallback(
    (changes: any) => {
      onNodesChange(changes);
      // Debounce IR updates for drag events
      const hasPositionChange = changes.some((c: any) => c.type === 'position' && !c.dragging);
      if (hasPositionChange) {
        setTimeout(updateIR, 0);
      }
    },
    [onNodesChange, updateIR]
  );

  // Handle node deletion
  const onNodesDelete = useCallback(() => {
    setTimeout(updateIR, 0);
  }, [updateIR]);

  // Handle selection changes - notify LiveView
  const handleSelectionChange: OnSelectionChangeFunc = useCallback(({ nodes: selectedNodes, edges: selectedEdges }) => {
    if (selectedNodes.length === 1) {
      const node = selectedNodes[0];
      onSelectionChange?.({
        nodeId: node.id,
        nodeType: node.type,
        nodeData: node.data as PipelineNodeData,
      });
    } else if (selectedEdges.length === 1) {
      const edge = selectedEdges[0];
      onSelectionChange?.({
        edgeId: edge.id,
        edgeData: {
          source: edge.source,
          target: edge.target,
          label: edge.label as string | undefined,
        },
      });
    } else {
      onSelectionChange?.({});
    }
  }, [onSelectionChange]);

  // Expose updateNodeData and updateEdgeLabel methods to parent via ref
  useImperativeHandle(ref, () => ({
    updateNodeData: (nodeId: string, data: Partial<PipelineNodeData>) => {
      setNodes((nds) => nds.map((node) => {
        if (node.id === nodeId) {
          return { ...node, data: { ...node.data, ...data } };
        }
        return node;
      }));
      setTimeout(updateIR, 0);
    },
    updateEdgeLabel: (edgeId: string, label: string) => {
      setEdges((eds) => eds.map((edge) => {
        if (edge.id === edgeId) {
          return { ...edge, label: label || undefined };
        }
        return edge;
      }));
      setTimeout(updateIR, 0);
    },
    addNode,
  }), [setNodes, setEdges, updateIR, addNode]);

  return (
    <div ref={reactFlowWrapper} className="w-full h-full">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={handleNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onDrop={onDrop}
        onDragOver={onDragOver}
        onNodesDelete={onNodesDelete}
        onSelectionChange={handleSelectionChange}
        nodeTypes={nodeTypes}
        fitView
        fitViewOptions={{ padding: 0.4, maxZoom: 0.8 }}
        minZoom={0.25}
        maxZoom={2}
        defaultEdgeOptions={{
          type: 'smoothstep',
          style: { strokeWidth: 2 },
          markerEnd: { type: MarkerType.ArrowClosed, width: 20, height: 20 },
        }}
        className="bg-base-200"
      >
        <Controls className="!bg-base-100 !border-base-300 !shadow-lg" />
        <Background
          variant={BackgroundVariant.Dots}
          gap={20}
          size={1}
          className="!bg-base-200"
        />
      </ReactFlow>
    </div>
  );
});

const PipelineCanvas = forwardRef<PipelineCanvasHandle, PipelineCanvasInnerProps>(
  function PipelineCanvas(props, ref) {
    return (
      <ReactFlowProvider>
        <PipelineCanvasInner ref={ref} {...props} />
      </ReactFlowProvider>
    );
  }
);

export default PipelineCanvas;
