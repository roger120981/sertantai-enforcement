import { writable } from 'svelte/store';
import { browser } from '$app/environment';

interface User {
	id: string;
	email: string;
	name?: string;
	github_login?: string;
	avatar_url?: string;
	is_admin: boolean;
}

interface AuthState {
	token: string | null;
	user: User | null;
	isAuthenticated: boolean;
}

// Initialize from localStorage if in browser
const initialState: AuthState = {
	token: browser ? localStorage.getItem('auth_token') : null,
	user: null,
	isAuthenticated: false
};

function createAuthStore() {
	const { subscribe, set, update } = writable<AuthState>(initialState);

	return {
		subscribe,
		setToken: (token: string) => {
			if (browser) {
				localStorage.setItem('auth_token', token);
			}
			update(state => ({ ...state, token, isAuthenticated: true }));
		},
		setUser: (user: User) => {
			update(state => ({ ...state, user, isAuthenticated: true }));
		},
		logout: () => {
			if (browser) {
				localStorage.removeItem('auth_token');
			}
			set({ token: null, user: null, isAuthenticated: false });
		},
		// Initialize user from token
		initializeFromToken: async (token: string) => {
			try {
				const response = await fetch('http://localhost:4002/api/user', {
					headers: {
						'Authorization': `Bearer ${token}`,
						'Content-Type': 'application/json'
					}
				});

				if (!response.ok) {
					throw new Error('Invalid token');
				}

				const user = await response.json();
				update(state => ({ ...state, user, token, isAuthenticated: true }));
				return user;
			} catch (error) {
				// Invalid token, clear it
				if (browser) {
					localStorage.removeItem('auth_token');
				}
				set({ token: null, user: null, isAuthenticated: false });
				throw error;
			}
		}
	};
}

export const authStore = createAuthStore();
