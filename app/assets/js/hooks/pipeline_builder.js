/**
 * Phoenix LiveView hook for the Pipeline Builder.
 *
 * This hook manages the connection between LiveView and the React Flow-based
 * visual pipeline builder. It lazy-loads the React bundle and handles
 * communication between React and LiveView.
 */

let builderModule = null;
let cssLoaded = false;

// Load the React Flow CSS dynamically
function loadBuilderCSS() {
  if (cssLoaded) return Promise.resolve();

  return new Promise((resolve) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/assets/js/index.css';
    link.onload = () => {
      cssLoaded = true;
      resolve();
    };
    link.onerror = () => {
      console.warn('Failed to load builder CSS');
      resolve(); // Don't block on CSS failure
    };
    document.head.appendChild(link);
  });
}

const PipelineBuilder = {
  async mounted() {
    // Parse data from LiveView
    this.initialIR = JSON.parse(this.el.dataset.initialIr || '{"version":"1.0","steps":[]}');
    this.availableSinks = JSON.parse(this.el.dataset.availableSinks || '[]');
    this.pipelineId = this.el.dataset.pipelineId;

    // Create container for React
    // React Flow requires explicit height - use absolute positioning to fill parent
    this.container = document.createElement('div');
    this.container.style.cssText = 'position: absolute; top: 0; left: 0; right: 0; bottom: 0;';
    this.el.style.position = 'relative';
    this.el.innerHTML = '';
    this.el.appendChild(this.container);

    // Load and mount React Flow
    try {
      // Load CSS and JS in parallel
      // Note: Dynamic import uses absolute URL path for runtime loading
      if (!builderModule) {
        const [module] = await Promise.all([
          import('/assets/js/index.js'),
          loadBuilderCSS(),
        ]);
        builderModule = module;
      }

      // Store the builder instance for later use (e.g., updating node data)
      this.builderInstance = builderModule.mountBuilder({
        element: this.container,
        initialIR: this.initialIR,
        availableSinks: this.availableSinks,
        pipelineId: this.pipelineId,
        sourceQueue: this.getSourceQueue(),
        onIRChange: (ir) => this.handleIRChange(ir),
        onSave: () => this.handleSave(),
        onSelectionChange: (selection) => this.handleSelectionChange(selection),
      });

      // Listen for node data updates from LiveView
      this.handleEvent('update_node_data', ({ nodeId, data }) => {
        if (this.builderInstance) {
          this.builderInstance.updateNodeData(nodeId, data);
        }
      });

      // Listen for edge label updates from LiveView
      this.handleEvent('update_edge_label', ({ edgeId, label }) => {
        if (this.builderInstance) {
          this.builderInstance.updateEdgeLabel(edgeId, label);
        }
      });

      console.log('PipelineBuilder mounted successfully');
    } catch (error) {
      console.error('Failed to load Pipeline Builder:', error);
      this.showError('Failed to load the visual builder. Please refresh the page.');
    }

    // Set up drag events for the sidebar
    this.setupDragListeners();
  },

  updated() {
    // Handle LiveView updates if needed
  },

  destroyed() {
    // Cleanup React
    if (builderModule && this.container) {
      try {
        builderModule.unmountBuilder(this.container);
      } catch (e) {
        console.warn('Error unmounting builder:', e);
      }
    }
    this.builderInstance = null;
    this.removeDragListeners();
    console.log('PipelineBuilder destroyed');
  },

  // Get source queue from sibling input
  getSourceQueue() {
    const input = document.querySelector('input[name="source_queue"]');
    return input?.value || 'events.incoming';
  },

  // Handle IR changes from React
  handleIRChange(ir) {
    this.currentIR = ir;
    this.pushEvent('update_ir', { ir: JSON.stringify(ir) });
  },

  // Handle save request from React
  handleSave() {
    this.pushEvent('save', {});
  },

  // Handle selection changes from React
  handleSelectionChange(selection) {
    this.pushEvent('select_node', selection);
  },

  // Show error message
  showError(message) {
    this.el.innerHTML = `
      <div class="h-full flex items-center justify-center text-error">
        <div class="text-center">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 mx-auto mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <p class="text-lg font-medium">${message}</p>
        </div>
      </div>
    `;
  },

  // Set up drag listeners for sidebar nodes
  setupDragListeners() {
    this.handleDragStart = (event) => {
      const nodeType = event.target.closest('[data-node-type]')?.dataset.nodeType;
      const sinkId = event.target.closest('[data-sink-id]')?.dataset.sinkId;

      if (nodeType) {
        event.dataTransfer.setData('application/reactflow/type', nodeType);
        if (sinkId) {
          event.dataTransfer.setData('application/reactflow/sinkId', sinkId);
        }
        event.dataTransfer.effectAllowed = 'move';
      }
    };

    // Listen on the entire document for sidebar drag events
    document.addEventListener('dragstart', this.handleDragStart);
  },

  removeDragListeners() {
    if (this.handleDragStart) {
      document.removeEventListener('dragstart', this.handleDragStart);
    }
  },
};

export default PipelineBuilder;
