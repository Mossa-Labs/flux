/**
 * Type definitions for the Pipeline Builder
 */

// Source configuration for different source types
export interface SourceConfig {
  type: 'queue' | 'webhook' | 'scheduled_poll';
  // Queue source
  queue?: string;
  prefetchCount?: number;
  ackMode?: 'auto' | 'manual';
  // Webhook source
  webhookPath?: string;
  authMethod?: 'none' | 'bearer' | 'basic';
  allowedContentTypes?: string[];
  // Scheduled poll source
  pollUrl?: string;
  pollInterval?: number;
  pollMethod?: 'GET' | 'POST';
  pollHeaders?: Record<string, string>;
}

// IR node definition (source and sink nodes stored in IR)
export interface IRNode {
  id: string;
  type: 'source' | 'sink';
  label: string;
  position: { x: number; y: number };
  // Source-specific
  sourceConfig?: SourceConfig;
  // Sink-specific
  sinkType?: string;
  sinkId?: number;
  sinkName?: string;
  queue?: string;
}

// IR edge definition
export interface IREdge {
  id: string;
  source: string;
  target: string;
  label?: string;
}

// Pipeline IR (Intermediate Representation) types
export interface PipelineIR {
  version: string;
  steps: StepIR[];
  nodes?: IRNode[];
  edges?: IREdge[];
}

export interface StepIR {
  id: string;
  type: 'native' | 'script' | 'ai';
  operation?: string;
  config?: Record<string, unknown>;
  // Script step specific fields (when type === 'script')
  language?: string;
  code?: string;
  timeout_ms?: number;
}

// Sink configuration from backend
export interface SinkConfig {
  id: number;
  name: string;
  type: 'http' | 's3' | 'postgres';
  enabled: boolean;
}

// Node data types for React Flow
// Index signatures added for React Flow compatibility
export interface SourceNodeData {
  label: string;
  queue?: string;
  sourceType?: 'queue' | 'webhook' | 'scheduled_poll';
  sourceConfig?: SourceConfig;
  [key: string]: unknown;
}

export interface StepNodeData {
  label: string;
  stepType: 'filter' | 'map' | 'rename' | 'script' | 'anomaly';
  config: Record<string, unknown>;
  [key: string]: unknown;
}

export interface SinkNodeData {
  label: string;
  sinkId?: number;
  sinkType?: string;
  sinkName?: string;
  queue?: string;
  [key: string]: unknown;
}

export interface QueueNodeData {
  label: string;
  queue?: string;
  [key: string]: unknown;
}

export type PipelineNodeData = SourceNodeData | StepNodeData | SinkNodeData | QueueNodeData;

// Selection info passed to LiveView
export interface SelectionInfo {
  nodeId?: string;
  nodeType?: string;
  nodeData?: PipelineNodeData;
  edgeId?: string;
  edgeData?: {
    source: string;
    target: string;
    label?: string;
  };
}

// Props for the builder
export interface BuilderProps {
  initialIR: PipelineIR;
  availableSinks: SinkConfig[];
  pipelineId?: string;
  onIRChange: (ir: PipelineIR) => void;
  onSave: () => void;
  onSelectionChange?: (selection: SelectionInfo) => void;
}

// Handle for external updates to node data
export interface PipelineCanvasHandle {
  updateNodeData: (nodeId: string, data: Partial<PipelineNodeData>) => void;
  updateEdgeLabel: (edgeId: string, label: string) => void;
}
