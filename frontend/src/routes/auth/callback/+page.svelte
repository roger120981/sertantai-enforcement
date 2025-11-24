<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { authStore } from '$lib/stores/auth';

	let status: 'loading' | 'success' | 'error' = 'loading';
	let errorMessage = '';

	onMount(async () => {
		try {
			// Get token from URL params
			const token = $page.url.searchParams.get('token');

			if (!token) {
				throw new Error('No authentication token received');
			}

			// Store token in localStorage and auth store
			localStorage.setItem('auth_token', token);

			// Update auth store
			authStore.setToken(token);

			// Fetch user info with the token
			const response = await fetch('http://localhost:4002/api/user', {
				headers: {
					'Authorization': `Bearer ${token}`,
					'Content-Type': 'application/json'
				}
			});

			if (!response.ok) {
				throw new Error('Failed to fetch user information');
			}

			const user = await response.json();
			authStore.setUser(user);

			status = 'success';

			// Redirect to dashboard after 1 second
			setTimeout(() => {
				goto('/dashboard');
			}, 1000);
		} catch (error) {
			console.error('Authentication error:', error);
			status = 'error';
			errorMessage = error instanceof Error ? error.message : 'Authentication failed';

			// Redirect to home after 3 seconds
			setTimeout(() => {
				goto('/');
			}, 3000);
		}
	});
</script>

<div class="flex min-h-screen items-center justify-center bg-gray-50">
	<div class="w-full max-w-md rounded-lg bg-white p-8 shadow-lg">
		{#if status === 'loading'}
			<div class="text-center">
				<div class="mb-4 inline-block h-12 w-12 animate-spin rounded-full border-4 border-solid border-primary border-r-transparent motion-reduce:animate-[spin_1.5s_linear_infinite]"></div>
				<h2 class="mb-2 text-xl font-semibold text-gray-900">Completing Sign In...</h2>
				<p class="text-gray-600">Please wait while we set up your session.</p>
			</div>
		{:else if status === 'success'}
			<div class="text-center">
				<div class="mb-4 text-green-500">
					<svg class="mx-auto h-16 w-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
					</svg>
				</div>
				<h2 class="mb-2 text-xl font-semibold text-gray-900">Success!</h2>
				<p class="text-gray-600">Redirecting to dashboard...</p>
			</div>
		{:else}
			<div class="text-center">
				<div class="mb-4 text-red-500">
					<svg class="mx-auto h-16 w-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
					</svg>
				</div>
				<h2 class="mb-2 text-xl font-semibold text-gray-900">Authentication Failed</h2>
				<p class="text-gray-600">{errorMessage}</p>
				<p class="mt-2 text-sm text-gray-500">Redirecting to home...</p>
			</div>
		{/if}
	</div>
</div>
