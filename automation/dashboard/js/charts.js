/**
 * SignLanguageTranslate Automation Dashboard
 * Chart rendering with Chart.js
 */

let iterationsChart = null;
let durationChart = null;

function updateCharts(history, analytics) {
    if (!history || !history.phases || history.phases.length === 0) {
        return;
    }
    
    const phases = history.phases;
    const labels = phases.map(p => p.id);
    const iterations = phases.map(p => p.total_iterations || 0);
    const durations = phases.map(p => (p.total_duration_seconds || 0) / 60); // Convert to minutes
    
    updateIterationsChart(labels, iterations);
    updateDurationChart(labels, durations);
}

function updateIterationsChart(labels, data) {
    const ctx = document.getElementById('iterations-chart');
    if (!ctx) return;
    
    if (iterationsChart) {
        iterationsChart.data.labels = labels;
        iterationsChart.data.datasets[0].data = data;
        iterationsChart.update();
        return;
    }
    
    iterationsChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Iterations',
                data: data,
                backgroundColor: 'rgba(59, 130, 246, 0.5)',
                borderColor: 'rgba(59, 130, 246, 1)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        color: '#9CA3AF'
                    },
                    grid: {
                        color: 'rgba(75, 85, 99, 0.3)'
                    }
                },
                x: {
                    ticks: {
                        color: '#9CA3AF'
                    },
                    grid: {
                        color: 'rgba(75, 85, 99, 0.3)'
                    }
                }
            }
        }
    });
}

function updateDurationChart(labels, data) {
    const ctx = document.getElementById('duration-chart');
    if (!ctx) return;
    
    if (durationChart) {
        durationChart.data.labels = labels;
        durationChart.data.datasets[0].data = data;
        durationChart.update();
        return;
    }
    
    durationChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Duration (minutes)',
                data: data,
                backgroundColor: 'rgba(16, 185, 129, 0.2)',
                borderColor: 'rgba(16, 185, 129, 1)',
                borderWidth: 2,
                fill: true,
                tension: 0.3
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        color: '#9CA3AF',
                        callback: function(value) {
                            return value + 'm';
                        }
                    },
                    grid: {
                        color: 'rgba(75, 85, 99, 0.3)'
                    }
                },
                x: {
                    ticks: {
                        color: '#9CA3AF'
                    },
                    grid: {
                        color: 'rgba(75, 85, 99, 0.3)'
                    }
                }
            }
        }
    });
}

// Export for use by app.js
window.updateCharts = updateCharts;
