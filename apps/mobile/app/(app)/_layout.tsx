import { Redirect, Stack } from 'expo-router';
import { useAuth } from '../../lib/auth';
import { useHousehold } from '../../lib/household';
import { colors } from '../../lib/theme';

// Guards the authenticated area: bounce out if the session or household is gone.
export default function AppLayout() {
  const { session, loading: authLoading } = useAuth();
  const { current, loading: householdLoading } = useHousehold();

  if (authLoading || householdLoading) return null;
  if (!session) return <Redirect href="/sign-in" />;
  if (!current) return <Redirect href="/onboarding" />;

  return (
    <Stack screenOptions={{ headerStyle: { backgroundColor: colors.bg }, headerShadowVisible: false }}>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="shop/[id]" options={{ title: 'Shop' }} />
    </Stack>
  );
}
