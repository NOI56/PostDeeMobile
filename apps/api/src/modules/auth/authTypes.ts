export type AuthProvider = 'mock' | 'firebase';

export type AuthUser = {
  id: string;
  provider: AuthProvider;
  email?: string;
  displayName?: string;
  phoneNumber?: string;
  phoneVerified?: boolean;
  subscriptionPlan?: 'BASIC' | 'STARTER' | 'PRO';
};

export type FirebaseTokenVerifier = {
  verifyIdToken: (token: string) => Promise<AuthUser>;
};

export const readAuthUser = (locals: Record<string, unknown>) =>
  locals.authUser as AuthUser | undefined;
