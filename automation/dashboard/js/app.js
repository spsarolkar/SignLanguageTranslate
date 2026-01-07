/**
 * SignLanguageTranslate Automation Dashboard
 * Main application logic
 */

class Dashboard {
    constructor() {
        this.refreshInterval = 30000; // 30 seconds
        this.status = null;
        this.history = null;
        this.analytics = null;
        this.screenshots = null;
        
        this.initialize();
    }
    
    async initialize() {
        await this.refresh();
        this.startAutoRefresh();
    }
    
    async refresh() {
        try {
            await Promise.all([
                this.fetchStatus(),
                this.fetchHistory(),
                this.fetchAnalytics(),
                this.fetchScreenshots()
            ]);
            
            this.updateUI();
            this.updateLastUpdated();
        } catch (error) {
            console.error('Failed to refresh:', error);
        }
    }
    
    async fetchStatus() {
        try {
            const response = await fetch('data/status.json');
            this.status = await response.json();
        } catch (error) {
            console.error('Failed to fetch status:', error);
        }
    }
    
    async fetchHistory() {
        try {
            const response = await fetch('data/history.json');
            this.history = await response.json();
        } catch (error) {
            console.error('Failed to fetch history:', error);
        }
    }
    
    async fetchAnalytics() {
        try {
            const response = await fetch('data/analytics.json');
            this.analytics = await response.json();
        } catch (error) {
            console.error('Failed to fetch analytics:', error);
        }
    }
    
    async fetchScreenshots() {
        try {
            const response = await fetch('data/screenshots.json');
            this.screenshots = await response.json();
        } catch (error) {
            console.error('Failed to fetch screenshots:', error);
        }
    }
    
    updateUI() {
        this.updateStatusBanner();
        this.updateProgressCards();
        this.updateStatisticsCards();
        this.updatePhaseHistory();
        this.updateScreenshotsGallery();
        this.updateRateLimitWarning();
        
        // Update charts
        if (window.updateCharts) {
            window.updateCharts(this.history, this.analytics);
        }
    }
    
    updateStatusBanner() {
        if (!this.status) return;
        
        const statusIcon = document.getElementById('status-icon');
        const statusText = document.getElementById('status-text');
        const statusDetail = document.getElementById('status-detail');
        const statusBanner = document.getElementById('status-banner');
        const currentPhaseInfo = document.getElementById('current-phase-info');
        const currentPhase = document.getElementById('current-phase');
        const currentStep = document.getElementById('current-step');
        
        const statusConfig = {
            'NOT_STARTED': { icon: '⏳', text: 'Not Started', color: 'border-gray-600', detail: 'Automation has not been started yet' },
            'RUNNING': { icon: '🚀', text: 'Running', color: 'border-blue-500', detail: 'Automation is in progress' },
            'PAUSED': { icon: '⏸️', text: 'Paused', color: 'border-yellow-500', detail: 'Automation is paused' },
            'RATE_LIMITED': { icon: '⏳', text: 'Rate Limited', color: 'border-yellow-500', detail: 'Waiting for rate limit to clear' },
            'FAILED': { icon: '❌', text: 'Failed', color: 'border-red-500', detail: 'Automation encountered an error' },
            'COMPLETE': { icon: '✅', text: 'Complete', color: 'border-green-500', detail: 'All phases completed successfully!' }
        };
        
        const config = statusConfig[this.status.status] || statusConfig['NOT_STARTED'];
        
        statusIcon.textContent = config.icon;
        statusText.textContent = config.text;
        statusDetail.textContent = config.detail;
        
        // Update border color
        statusBanner.className = statusBanner.className.replace(/border-\w+-\d+/g, '');
        statusBanner.classList.add(config.color);
        
        // Show current phase if running
        if (this.status.current_phase) {
            currentPhaseInfo.classList.remove('hidden');
            currentPhase.textContent = `Phase ${this.status.current_phase}`;
            currentStep.textContent = `Step: ${this.status.current_step || '-'} (Iteration ${this.status.current_iteration || 0})`;
        } else {
            currentPhaseInfo.classList.add('hidden');
        }
    }
    
    updateProgressCards() {
        if (!this.status) return;
        
        const progress = this.status.overall_progress || {};
        const stats = this.status.statistics || {};
        
        // Progress percentage
        const percentage = progress.percentage || 0;
        document.getElementById('progress-text').textContent = `${Math.round(percentage)}%`;
        document.getElementById('progress-bar').style.width = `${percentage}%`;
        
        // Phases
        const completed = progress.completed_phases || 0;
        const total = progress.total_phases || 0;
        document.getElementById('phases-text').textContent = `${completed} / ${total}`;
        
        // Iterations
        const iterations = stats.total_iterations || 0;
        const avgIterations = stats.avg_iterations_per_phase || 0;
        document.getElementById('iterations-text').textContent = iterations.toLocaleString();
        document.getElementById('avg-iterations').textContent = `Avg: ${avgIterations.toFixed(1)} per phase`;
        
        // Duration
        const minutes = stats.total_duration_minutes || 0;
        document.getElementById('duration-text').textContent = this.formatDuration(minutes * 60);
    }
    
    updateStatisticsCards() {
        if (!this.status) return;
        
        const stats = this.status.statistics || {};
        
        document.getElementById('build-errors').textContent = (stats.total_build_errors || 0).toLocaleString();
        document.getElementById('test-failures').textContent = (stats.total_test_failures || 0).toLocaleString();
        document.getElementById('rate-limits').textContent = (stats.total_rate_limits || 0).toLocaleString();
        
        const tokens = (stats.total_input_tokens || 0) + (stats.total_output_tokens || 0);
        document.getElementById('tokens-used').textContent = this.formatNumber(tokens);
    }
    
    updatePhaseHistory() {
        const container = document.getElementById('phase-history');
        if (!this.history || !this.history.phases || this.history.phases.length === 0) {
            container.innerHTML = '<p class="text-gray-500">No phases completed yet.</p>';
            return;
        }
        
        const html = this.history.phases.map(phase => {
            const statusIcon = phase.status === 'completed' ? '✅' : phase.status === 'failed' ? '❌' : '🔄';
            const statusClass = phase.status === 'completed' ? 'text-green-400' : phase.status === 'failed' ? 'text-red-400' : 'text-blue-400';
            const duration = this.formatDuration(phase.total_duration_seconds || 0);
            
            return `
                <div class="flex items-center justify-between p-3 bg-gray-700/50 rounded-lg">
                    <div class="flex items-center space-x-3">
                        <span class="text-xl">${statusIcon}</span>
                        <div>
                            <p class="font-medium">${phase.name || phase.id}</p>
                            <p class="text-sm text-gray-400">Phase ${phase.id}</p>
                        </div>
                    </div>
                    <div class="text-right">
                        <p class="${statusClass} font-medium">${phase.status}</p>
                        <p class="text-sm text-gray-500">${phase.total_iterations || 0} iterations • ${duration}</p>
                    </div>
                </div>
            `;
        }).join('');
        
        container.innerHTML = html;
    }
    
    updateScreenshotsGallery() {
        const container = document.getElementById('screenshots-gallery');
        if (!this.screenshots || !this.screenshots.screenshots || this.screenshots.screenshots.length === 0) {
            container.innerHTML = '<p class="text-gray-500 col-span-full">No screenshots captured yet.</p>';
            return;
        }
        
        const html = this.screenshots.screenshots.map(screenshot => {
            return `
                <div class="relative group cursor-pointer" onclick="window.open('screenshots/${screenshot.filename}', '_blank')">
                    <img src="screenshots/${screenshot.filename}" alt="${screenshot.filename}" 
                         class="rounded-lg border border-gray-700 hover:border-blue-500 transition-colors w-full h-32 object-cover">
                    <div class="absolute bottom-0 left-0 right-0 bg-black/75 p-2 rounded-b-lg opacity-0 group-hover:opacity-100 transition-opacity">
                        <p class="text-xs truncate">${screenshot.filename}</p>
                    </div>
                </div>
            `;
        }).join('');
        
        container.innerHTML = html;
    }
    
    updateRateLimitWarning() {
        const warning = document.getElementById('rate-limit-warning');
        const message = document.getElementById('rate-limit-message');
        
        if (!this.status || !this.status.rate_limit_status) {
            warning.classList.add('hidden');
            return;
        }
        
        const rateLimit = this.status.rate_limit_status;
        
        if (rateLimit.is_limited && rateLimit.wait_until) {
            warning.classList.remove('hidden');
            const waitUntil = new Date(rateLimit.wait_until);
            const now = new Date();
            const remainingSeconds = Math.max(0, Math.floor((waitUntil - now) / 1000));
            
            if (remainingSeconds > 0) {
                message.textContent = `Waiting ${this.formatDuration(remainingSeconds)} before retrying...`;
            } else {
                message.textContent = 'Rate limit should clear soon...';
            }
        } else {
            warning.classList.add('hidden');
        }
    }
    
    updateLastUpdated() {
        const element = document.getElementById('last-updated');
        if (this.status && this.status.last_updated) {
            const date = new Date(this.status.last_updated);
            element.textContent = `Updated: ${date.toLocaleTimeString()}`;
        }
    }
    
    startAutoRefresh() {
        setInterval(() => this.refresh(), this.refreshInterval);
    }
    
    formatDuration(seconds) {
        if (seconds < 60) return `${Math.round(seconds)}s`;
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return `${hours}h ${minutes}m`;
    }
    
    formatNumber(num) {
        if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
        if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
        return num.toLocaleString();
    }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.dashboard = new Dashboard();
});
