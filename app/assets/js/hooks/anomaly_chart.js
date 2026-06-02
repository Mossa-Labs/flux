import uPlot from "uplot"
import "uplot/dist/uPlot.min.css"

const COLORS = ["#6366f1", "#ec4899", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#f97316"]

const AnomalyChart = {
  mounted() {
    this.chart = null
    this.resizeObserver = new ResizeObserver(() => {
      if (this.chart) {
        this.chart.setSize({ width: this.el.clientWidth, height: 300 })
      }
    })
    this.resizeObserver.observe(this.el)

    this.handleEvent("chart-data", ({ series, labels, timestamps }) => {
      this.renderChart(series, labels, timestamps)
    })
  },

  renderChart(series, labels, timestamps) {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }

    if (!timestamps || timestamps.length === 0) {
      this.el.innerHTML = '<div class="flex items-center justify-center h-[300px] text-base-content/40">No data available</div>'
      return
    }

    // Clear any placeholder content
    this.el.innerHTML = ""

    const seriesConfig = [
      { label: "Index" },
      ...labels.map((label, i) => ({
        label: label,
        stroke: COLORS[i % COLORS.length],
        width: 2,
        points: { show: false },
      }))
    ]

    const opts = {
      width: this.el.clientWidth,
      height: 300,
      series: seriesConfig,
      axes: [
        {
          label: "Sample",
          stroke: "#6b7280",
          grid: { stroke: "rgba(107, 114, 128, 0.1)" },
        },
        {
          label: "Value",
          stroke: "#6b7280",
          grid: { stroke: "rgba(107, 114, 128, 0.1)" },
        }
      ],
      scales: {
        x: { time: false },
        y: { auto: true },
      },
      cursor: {
        drag: { x: true, y: false },
      },
      legend: {
        show: true,
      },
    }

    const data = [timestamps, ...series]

    this.chart = new uPlot(opts, data, this.el)
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  }
}

export default AnomalyChart
