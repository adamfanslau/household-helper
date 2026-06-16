import { Redirect } from 'expo-router';
import { ActivityIndicator, View } from 'react-native';
import { useAuth } from '../lib/auth';
import { useHousehold } from '../lib/household';
import { colors } from '../lib/theme';

// Entry gate: routes to sign-in, onboarding, or the app based on session +
// household membership.
export default function Index() {
  const { session, loading: authLoading } = useAuth();
  const { current, loading: householdLoading } = useHousehold();

  if (authLoading || (session && householdLoading)) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.bg }}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  if (!session) return <Redirect href="/sign-in" />;
  if (!current) return <Redirect href="/onboarding" />;
  return <Redirect href="/(app)/(tabs)" />;
}
