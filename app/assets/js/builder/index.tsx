/**
 * Pipeline Builder React Application
 *
 * This module provides the entry points for mounting and unmounting
 * the React Flow-based visual pipeline builder.
 */

import React, { createRef } from 'react';
import { createRoot, Root } from 'react-dom/client';
import PipelineCanvas from './PipelineCanvas';
import type { PipelineIR, SinkConfig, SelectionInfo, PipelineCanvasHandle, PipelineNodeData } from './types';

interface MountOptions {
  element: HTMLElement;
  initialIR: PipelineIR;
  availableSinks: SinkConfig[];
  pipelineId?: string;
  sourceQueue?: string;
  onIRChange: (ir: PipelineIR) => void;
  onSave: () => void;
  onSelectionChange?: (selection: SelectionInfo) => void;
}

// Builder instance returned from mountBuilder
export interface BuilderInstance {
  updateNodeData: (nodeId: string, data: Partial<PipelineNodeData>) => void;
  updateEdgeLabel: (edgeId: string, label: string) => void;
}

// Store roots and refs for cleanup
const roots = new Map<HTMLElement, Root>();
const canvasRefs = new Map<HTMLElement, React.RefObject<PipelineCanvasHandle>>();

/**
 * Mount the pipeline builder React application
 * Returns an instance with methods to interact with the canvas
 */
export function mountBuilder(options: MountOptions): BuilderInstance {
  const { element, initialIR, availableSinks, pipelineId, sourceQueue, onIRChange, onSave, onSelectionChange } = options;

  // Clean up existing root if present
  if (roots.has(element)) {
    roots.get(element)?.unmount();
    roots.delete(element);
    canvasRefs.delete(element);
  }

  const root = createRoot(element);
  const canvasRef = createRef<PipelineCanvasHandle>();

  roots.set(element, root);
  canvasRefs.set(element, canvasRef);

  root.render(
    <React.StrictMode>
      <PipelineCanvas
        ref={canvasRef}
        initialIR={initialIR}
        availableSinks={availableSinks}
        pipelineId={pipelineId}
        sourceQueue={sourceQueue}
        onIRChange={onIRChange}
        onSave={onSave}
        onSelectionChange={onSelectionChange}
      />
    </React.StrictMode>
  );

  // Return instance with methods to interact with canvas
  return {
    updateNodeData: (nodeId: string, data: Partial<PipelineNodeData>) => {
      canvasRef.current?.updateNodeData(nodeId, data);
    },
    updateEdgeLabel: (edgeId: string, label: string) => {
      canvasRef.current?.updateEdgeLabel(edgeId, label);
    },
  };
}

/**
 * Unmount the pipeline builder React application
 */
export function unmountBuilder(element: HTMLElement): void {
  const root = roots.get(element);
  if (root) {
    root.unmount();
    roots.delete(element);
  }
}

// Export types for TypeScript consumers
export type { PipelineIR, SinkConfig, SelectionInfo, PipelineNodeData, MountOptions, BuilderInstance };
