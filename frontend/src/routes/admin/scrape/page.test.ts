import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/svelte';
import { get } from 'svelte/store';
import ScrapePage from './+page.svelte';
import * as scrapingQuery from '$lib/query/scraping';
import * as sseStore from '$lib/stores/sse';

// Mock scraping query module
vi.mock('$lib/query/scraping', () => ({
	useStartScrapingMutation: vi.fn(),
	useStopScrapingMutation: vi.fn()
}));

// Mock SSE store module
vi.mock('$lib/stores/sse', () => ({
	createSSEStore: vi.fn()
}));

// Mock child components - don't mock them, let them load
// If they have issues, we'll mock their dependencies instead

describe('Admin Scrape Page (+page.svelte)', () => {
	// Helper to create Svelte-compatible store
	function createMockStore(value: any) {
		return {
			subscribe: (fn: (value: any) => void) => {
				fn(value);
				return {
					unsubscribe: () => {}
				};
			}
		};
	}

	// Mock mutation response
	const mockStartMutation = {
		mutate: vi.fn(),
		isPending: false,
		isError: false,
		error: null
	};

	const mockStopMutation = {
		mutate: vi.fn(),
		isPending: false,
		isError: false,
		error: null
	};

	// Mock SSE store
	const mockSSEStore = createMockStore({
		connected: false,
		lastEvent: null,
		error: null
	});

	const mockSSEMethods = {
		connect: vi.fn(),
		disconnect: vi.fn()
	};

	beforeEach(() => {
		vi.clearAllMocks();

		// Setup mutation mocks
		vi.mocked(scrapingQuery.useStartScrapingMutation).mockReturnValue(
			createMockStore(mockStartMutation)
		);
		vi.mocked(scrapingQuery.useStopScrapingMutation).mockReturnValue(
			createMockStore(mockStopMutation)
		);

		// Setup SSE store mock
		vi.mocked(sseStore.createSSEStore).mockReturnValue({
			...mockSSEStore,
			...mockSSEMethods
		} as any);
	});

	describe('Mounting and Initialization', () => {
		it('mounts successfully with main heading', () => {
			render(ScrapePage);

			expect(screen.getByText('UK Enforcement Data Scraping')).toBeInTheDocument();
			expect(
				screen.getByText(/Manually trigger enforcement data scraping from UK regulatory agencies/)
			).toBeInTheDocument();
		});

		it('displays scraping configuration section', () => {
			render(ScrapePage);

			expect(screen.getByText('Scraping Configuration')).toBeInTheDocument();
		});

		it('displays navigation links to admin dashboard and sessions', () => {
			render(ScrapePage);

			const adminLink = screen.getByRole('link', { name: /Admin Dashboard/i });
			expect(adminLink).toHaveAttribute('href', '/admin');

			const sessionsLink = screen.getByRole('link', { name: /View Sessions/i });
			expect(sessionsLink).toHaveAttribute('href', '/admin/scrape-sessions');
		});

		it('initializes with default HSE agency selected', () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			expect(agencySelect).toHaveValue('hse');
		});

		it('initializes with notices database as default', () => {
			render(ScrapePage);

			const databaseSelect = screen.getByRole('combobox', { name: /Enforcement Type/i });
			expect(databaseSelect).toHaveValue('notices');
		});

		it('shows "Ready to start scraping" status initially', () => {
			render(ScrapePage);

			expect(screen.getByText('Ready to start scraping')).toBeInTheDocument();
		});
	});

	describe('Agency Selection', () => {
		it('displays all agency options in dropdown', () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			expect(agencySelect).toBeInTheDocument();

			// Check all agencies are available as options
			expect(screen.getByRole('option', { name: /HSE \(Health & Safety Executive\)/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /Environment Agency \(EA\)/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /SEPA/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /NRW/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /CAA \(Civil Aviation Authority\)/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /OPSS/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /ORR/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /FRA/i })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: /MCA/i })).toBeInTheDocument();
		});

		it('displays both HSE and EA agency buttons', () => {
			render(ScrapePage);

			expect(
				screen.getByRole('option', { name: /HSE \(Health & Safety Executive\)/i })
			).toBeInTheDocument();
			expect(
				screen.getByRole('option', { name: /Environment Agency \(EA\)/i })
			).toBeInTheDocument();
		});

		it('allows selecting Environment Agency', async () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			await fireEvent.change(agencySelect, { target: { value: 'ea' } });

			expect(agencySelect).toHaveValue('ea');
		});

		it('allows selecting CAA agency', async () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			await fireEvent.change(agencySelect, { target: { value: 'caa' } });

			expect(agencySelect).toHaveValue('caa');
		});

		it('switches from EA back to HSE', async () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });

			// Select EA
			await fireEvent.change(agencySelect, { target: { value: 'ea' } });
			expect(agencySelect).toHaveValue('ea');

			// Select HSE
			await fireEvent.change(agencySelect, { target: { value: 'hse' } });
			expect(agencySelect).toHaveValue('hse');
		});

		it('shows Start Page input for HSE agency', () => {
			render(ScrapePage);

			const startPageLabel = screen.getByLabelText(/Start Page/i);
			expect(startPageLabel).toBeInTheDocument();
			expect(startPageLabel).toHaveAttribute('type', 'number');
		});

		it('shows From Date input for EA agency', async () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			await fireEvent.change(agencySelect, { target: { value: 'ea' } });

			const fromDateLabel = screen.getByLabelText(/From Date/i);
			expect(fromDateLabel).toBeInTheDocument();
			expect(fromDateLabel).toHaveAttribute('type', 'date');
		});

		it('shows Max Pages input for HSE agency', () => {
			render(ScrapePage);

			const maxPagesLabel = screen.getByLabelText(/Max Pages/i);
			expect(maxPagesLabel).toBeInTheDocument();
			expect(maxPagesLabel).toHaveAttribute('type', 'number');
		});

		it('shows To Date input for EA agency', async () => {
			render(ScrapePage);

			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			await fireEvent.change(agencySelect, { target: { value: 'ea' } });

			const toDateLabel = screen.getByLabelText(/To Date/i);
			expect(toDateLabel).toBeInTheDocument();
			expect(toDateLabel).toHaveAttribute('type', 'date');
		});
	});

	describe('Database Selection', () => {
		it('displays enforcement type dropdown with all options', () => {
			render(ScrapePage);

			expect(screen.getByRole('option', { name: 'Enforcement Notices' })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: 'Convictions' })).toBeInTheDocument();
			expect(screen.getByRole('option', { name: 'Appeals' })).toBeInTheDocument();
		});

		it('allows selecting convictions database', async () => {
			render(ScrapePage);

			const databaseSelect = screen.getByRole('combobox', { name: /Enforcement Type/i });
			await fireEvent.change(databaseSelect, { target: { value: 'convictions' } });

			expect(databaseSelect).toHaveValue('convictions');
		});

		it('allows selecting appeals database', async () => {
			render(ScrapePage);

			const databaseSelect = screen.getByRole('combobox', { name: /Enforcement Type/i });
			await fireEvent.change(databaseSelect, { target: { value: 'appeals' } });

			expect(databaseSelect).toHaveValue('appeals');
		});
	});

	describe('Form State and Validation', () => {
		it('displays start page number input with min value 1', () => {
			render(ScrapePage);

			const startPageInput = screen.getByLabelText(/Start Page/i) as HTMLInputElement;
			expect(startPageInput.min).toBe('1');
		});

		it('displays max pages input with constraints', () => {
			render(ScrapePage);

			const maxPagesInput = screen.getByLabelText(/Max Pages/i) as HTMLInputElement;
			expect(maxPagesInput.min).toBe('1');
			expect(maxPagesInput.max).toBe('100');
		});

		it('allows user to input start page value', async () => {
			render(ScrapePage);

			const startPageInput = screen.getByLabelText(/Start Page/i);
			await fireEvent.input(startPageInput, { target: { value: '5' } });

			expect(startPageInput).toHaveValue(5);
		});

		it('allows user to input max pages value', async () => {
			render(ScrapePage);

			const maxPagesInput = screen.getByLabelText(/Max Pages/i);
			await fireEvent.input(maxPagesInput, { target: { value: '10' } });

			expect(maxPagesInput).toHaveValue(10);
		});

		it('shows process all records checkbox', () => {
			render(ScrapePage);

			const checkbox = screen.getByRole('checkbox');
			expect(checkbox).toBeInTheDocument();
			expect(screen.getByText('Process ALL records (including existing)')).toBeInTheDocument();
		});
	});

	describe('Start/Stop Scraping Actions', () => {
		it('displays Start Scraping button initially', () => {
			render(ScrapePage);

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			expect(startButton).toBeInTheDocument();
			expect(startButton).toHaveClass('bg-blue-600');
		});

		it('does not display Stop Scraping button initially', () => {
			render(ScrapePage);

			const stopButton = screen.queryByRole('button', { name: /Stop Scraping/i });
			expect(stopButton).not.toBeInTheDocument();
		});

		it('handles start scraping form submission', async () => {
			render(ScrapePage);

			// Setup mutation mock to handle the call
			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				// Simulate successful start
				callbacks?.onSuccess?.({
					data: {
						session_id: 'test-session-123',
						status: 'started'
					}
				});
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			// Should call the mutation
			expect(mockStartMutation.mutate).toHaveBeenCalled();

			// Should connect to SSE
			expect(mockSSEMethods.connect).toHaveBeenCalledWith('test-session-123');
		});

		it('sends correct parameters for HSE scraping', async () => {
			render(ScrapePage);

			// Set form values
			const startPageInput = screen.getByLabelText(/Start Page/i);
			await fireEvent.input(startPageInput, { target: { value: '2' } });

			const maxPagesInput = screen.getByLabelText(/Max Pages/i);
			await fireEvent.input(maxPagesInput, { target: { value: '5' } });

			const databaseSelect = screen.getByRole('combobox', { name: /Enforcement Type/i });
			await fireEvent.change(databaseSelect, { target: { value: 'convictions' } });

			mockStartMutation.mutate.mockImplementation((params) => {
				expect(params).toEqual({
					agency: 'hse',
					database: 'convictions',
					start_page: 2,
					max_pages: 5,
					country: 'All'
				});
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			expect(mockStartMutation.mutate).toHaveBeenCalled();
		});

		it('disables form controls when scraping is active', async () => {
			render(ScrapePage);

			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				callbacks?.onSuccess?.({
					data: { session_id: 'test-session-123' }
				});
			});

			// Start scraping
			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			// Wait for state update
			await new Promise((resolve) => setTimeout(resolve, 50));

			// Check that form controls are disabled
			const agencySelect = screen.getByRole('combobox', { name: /Agency/i });
			expect(agencySelect).toBeDisabled();

			const databaseSelect = screen.getByRole('combobox', { name: /Enforcement Type/i });
			expect(databaseSelect).toBeDisabled();
		});

		it('shows "Scraping in progress..." status when active', async () => {
			render(ScrapePage);

			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				callbacks?.onSuccess?.({
					data: { session_id: 'test-session-123' }
				});
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			// Wait for state update
			await new Promise((resolve) => setTimeout(resolve, 50));

			expect(screen.getByText('Scraping in progress...')).toBeInTheDocument();
		});

		it('shows Stop Scraping button when scraping is active', async () => {
			render(ScrapePage);

			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				callbacks?.onSuccess?.({
					data: { session_id: 'test-session-123' }
				});
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			// Wait for state update
			await new Promise((resolve) => setTimeout(resolve, 50));

			const stopButton = screen.getByRole('button', { name: /Stop Scraping/i });
			expect(stopButton).toBeInTheDocument();
			expect(stopButton).toHaveClass('bg-red-600');
		});

		it('handles stop scraping action', async () => {
			render(ScrapePage);

			// Start scraping first
			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				callbacks?.onSuccess?.({
					data: { session_id: 'test-session-123' }
				});
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			await new Promise((resolve) => setTimeout(resolve, 50));

			// Now stop it
			mockStopMutation.mutate.mockImplementation((sessionId, callbacks) => {
				expect(sessionId).toBe('test-session-123');
				callbacks?.onSuccess?.();
			});

			const stopButton = screen.getByRole('button', { name: /Stop Scraping/i });
			await fireEvent.click(stopButton);

			expect(mockStopMutation.mutate).toHaveBeenCalledWith(
				'test-session-123',
				expect.any(Object)
			);
			expect(mockSSEMethods.disconnect).toHaveBeenCalled();
		});

		it('shows loading state on start button when mutation is pending', () => {
			// Mock pending state
			vi.mocked(scrapingQuery.useStartScrapingMutation).mockReturnValue(
				createMockStore({
					...mockStartMutation,
					isPending: true
				})
			);

			render(ScrapePage);

			expect(screen.getByText('Starting...')).toBeInTheDocument();
		});

		it('handles start scraping error', async () => {
			// Mock window.alert
			global.alert = vi.fn();

			render(ScrapePage);

			mockStartMutation.mutate.mockImplementation((params, callbacks) => {
				callbacks?.onError?.(new Error('Network error'));
			});

			const startButton = screen.getByRole('button', { name: /Start Scraping/i });
			await fireEvent.click(startButton);

			expect(global.alert).toHaveBeenCalledWith('Failed to start scraping: Network error');
		});
	});

	describe('Scraped Records Display', () => {
		it('does not show errors panel when no errors', () => {
			render(ScrapePage);

			// Check specifically for the errors panel heading (not just the word "Errors" anywhere)
			// The errors panel has a specific structure with count
			expect(screen.queryByText(/Errors \(\d+\)/)).not.toBeInTheDocument();
		});
	});

	describe('Accessibility', () => {
		it('uses semantic form element', () => {
			const { container } = render(ScrapePage);

			const form = container.querySelector('form');
			expect(form).toBeInTheDocument();
		});

		it('labels all form inputs correctly', () => {
			render(ScrapePage);

			expect(screen.getByLabelText(/Enforcement Type/i)).toBeInTheDocument();
			expect(screen.getByLabelText(/Start Page/i)).toBeInTheDocument();
			expect(screen.getByLabelText(/Max Pages/i)).toBeInTheDocument();
		});

		it('uses proper heading hierarchy', () => {
			const { container } = render(ScrapePage);

			const h1 = container.querySelector('h1');
			expect(h1).toHaveTextContent('UK Enforcement Data Scraping');

			const h2 = container.querySelector('h2');
			expect(h2).toHaveTextContent('Scraping Configuration');
		});

		it('provides descriptive button text and labels', () => {
			render(ScrapePage);

			expect(screen.getByRole('button', { name: /Start Scraping/i })).toBeInTheDocument();
			expect(screen.getByRole('combobox', { name: /Agency/i })).toBeInTheDocument();
			expect(
				screen.getByRole('option', { name: /HSE \(Health & Safety Executive\)/i })
			).toBeInTheDocument();
			expect(
				screen.getByRole('option', { name: /Environment Agency \(EA\)/i })
			).toBeInTheDocument();
		});
	});
});
