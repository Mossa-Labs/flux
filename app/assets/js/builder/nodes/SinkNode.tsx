import React, { memo } from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import type { SinkNodeData } from '../types';

const sinkIcons: Record<string, React.ReactNode> = {
  http: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM4.332 8.027a6.012 6.012 0 011.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 019 7.5V8a2 2 0 004 0 2 2 0 011.523-1.943A5.977 5.977 0 0116 10c0 .34-.028.675-.083 1H15a2 2 0 00-2 2v2.197A5.973 5.973 0 0110 16v-2a2 2 0 00-2-2 2 2 0 01-2-2 2 2 0 00-1.668-1.973z" clipRule="evenodd" />
    </svg>
  ),
  s3: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path fillRule="evenodd" d="M5.5 17a4.5 4.5 0 01-1.44-8.765 4.5 4.5 0 018.302-3.046 3.5 3.5 0 014.504 4.272A4 4 0 0115 17H5.5zm3.75-2.75a.75.75 0 001.5 0V9.66l1.95 2.1a.75.75 0 101.1-1.02l-3.25-3.5a.75.75 0 00-1.1 0l-3.25 3.5a.75.75 0 101.1 1.02l1.95-2.1v4.59z" clipRule="evenodd" />
    </svg>
  ),
  postgres: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path fillRule="evenodd" d="M10 1c3.866 0 7 1.79 7 4s-3.134 4-7 4-7-1.79-7-4 3.134-4 7-4zm5.694 8.13c.464-.264.91-.583 1.306-.952V10c0 2.21-3.134 4-7 4s-7-1.79-7-4V8.178c.396.37.842.688 1.306.953C5.838 10.006 7.854 10.5 10 10.5s4.162-.494 5.694-1.37zM3 13.179V15c0 2.21 3.134 4 7 4s7-1.79 7-4v-1.822c-.396.37-.842.688-1.306.953-1.532.875-3.548 1.369-5.694 1.369s-4.162-.494-5.694-1.37A7.009 7.009 0 013 13.179z" clipRule="evenodd" />
    </svg>
  ),
  queue: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path d="M2 4.5A2.5 2.5 0 014.5 2h11a2.5 2.5 0 010 5h-11A2.5 2.5 0 012 4.5zM2.75 9.083a.75.75 0 000 1.5h14.5a.75.75 0 000-1.5H2.75zM2.75 12.663a.75.75 0 000 1.5h14.5a.75.75 0 000-1.5H2.75zM2.75 16.25a.75.75 0 000 1.5h14.5a.75.75 0 000-1.5H2.75z" />
    </svg>
  ),
};

const SinkNode = memo(({ data, selected }: NodeProps) => {
  const nodeData = data as SinkNodeData;
  const sinkType = nodeData.sinkType || 'queue';

  return (
    <div className={`px-4 py-3 bg-base-100 border-2 rounded-lg shadow-md min-w-[160px] ${
      selected ? 'border-secondary' : 'border-secondary/50'
    }`}>
      <Handle
        type="target"
        position={Position.Top}
        className="!bg-secondary !w-3 !h-3 !border-2 !border-base-100"
      />
      <div className="flex items-center gap-2 mb-1">
        <div className="p-1.5 bg-secondary/10 rounded text-secondary">
          {sinkIcons[sinkType] || sinkIcons.queue}
        </div>
        <span className="font-semibold text-sm">{nodeData.label || 'Output'}</span>
      </div>
      {nodeData.sinkName && (
        <div className="text-xs text-base-content/60 truncate">
          {nodeData.sinkName}
        </div>
      )}
      {nodeData.queue && (
        <div className="text-xs text-base-content/60 font-mono truncate">
          {nodeData.queue}
        </div>
      )}
    </div>
  );
});

SinkNode.displayName = 'SinkNode';

export default SinkNode;
