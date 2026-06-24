import React, { memo } from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import type { SourceNodeData } from '../types';

const sourceTypeIcons: Record<string, React.ReactNode> = {
  queue: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path d="M10.75 2.75a.75.75 0 00-1.5 0v8.614L6.295 8.235a.75.75 0 10-1.09 1.03l4.25 4.5a.75.75 0 001.09 0l4.25-4.5a.75.75 0 00-1.09-1.03l-2.955 3.129V2.75z" />
      <path d="M3.5 12.75a.75.75 0 00-1.5 0v2.5A2.75 2.75 0 004.75 18h10.5A2.75 2.75 0 0018 15.25v-2.5a.75.75 0 00-1.5 0v2.5c0 .69-.56 1.25-1.25 1.25H4.75c-.69 0-1.25-.56-1.25-1.25v-2.5z" />
    </svg>
  ),
  webhook: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path fillRule="evenodd" d="M4.25 2A2.25 2.25 0 002 4.25v11.5A2.25 2.25 0 004.25 18h11.5A2.25 2.25 0 0018 15.75V4.25A2.25 2.25 0 0015.75 2H4.25zm4.03 6.28a.75.75 0 00-1.06-1.06L4.97 9.47a.75.75 0 000 1.06l2.25 2.25a.75.75 0 001.06-1.06L6.56 10l1.72-1.72zm4.5-1.06a.75.75 0 10-1.06 1.06L13.44 10l-1.72 1.72a.75.75 0 101.06 1.06l2.25-2.25a.75.75 0 000-1.06l-2.25-2.25z" clipRule="evenodd" />
    </svg>
  ),
  scheduled_poll: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clipRule="evenodd" />
    </svg>
  ),
  kafka: (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
      <path d="M3 4.25A2.25 2.25 0 015.25 2h9.5A2.25 2.25 0 0117 4.25v11.5A2.25 2.25 0 0114.75 18h-9.5A2.25 2.25 0 013 15.75V4.25zm3 .5a.75.75 0 00-.75.75v9a.75.75 0 001.5 0v-9A.75.75 0 006 4.75zm4 0a.75.75 0 00-.75.75v9a.75.75 0 001.5 0v-9a.75.75 0 00-.75-.75zm4 0a.75.75 0 00-.75.75v9a.75.75 0 001.5 0v-9a.75.75 0 00-.75-.75z" />
    </svg>
  ),
};

function getSourceSubtitle(nodeData: SourceNodeData): string | null {
  const config = nodeData.sourceConfig;
  if (!config) {
    return nodeData.queue || null;
  }

  switch (config.type) {
    case 'queue':
      return config.queue || null;
    case 'webhook':
      return config.webhookPath || null;
    case 'scheduled_poll':
      if (config.pollUrl) {
        try {
          return new URL(config.pollUrl).hostname;
        } catch {
          return config.pollUrl;
        }
      }
      return null;
    case 'kafka':
      return config.topic || null;
    default:
      return nodeData.queue || null;
  }
}

const SourceNode = memo(({ data }: NodeProps) => {
  const nodeData = data as SourceNodeData;
  const sourceType = nodeData.sourceType || 'queue';
  const icon = sourceTypeIcons[sourceType] || sourceTypeIcons.queue;
  const subtitle = getSourceSubtitle(nodeData);

  return (
    <div className="px-4 py-3 bg-base-100 border-2 border-primary rounded-lg shadow-md min-w-[160px]">
      <div className="flex items-center gap-2 mb-2">
        <div className="p-1.5 bg-primary/10 rounded text-primary">
          {icon}
        </div>
        <span className="font-semibold text-sm">{nodeData.label || 'Source'}</span>
      </div>
      {subtitle && (
        <div className="text-xs text-base-content/60 font-mono truncate">
          {subtitle}
        </div>
      )}
      <Handle
        type="source"
        position={Position.Bottom}
        className="!bg-primary !w-3 !h-3 !border-2 !border-base-100"
      />
    </div>
  );
});

SourceNode.displayName = 'SourceNode';

export default SourceNode;
