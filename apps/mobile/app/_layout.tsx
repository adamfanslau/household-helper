import { Slot } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { AuthProvider } from '../lib/auth';
import { HouseholdProvider } from '../lib/household';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <AuthProvider>
        <HouseholdProvider>
          <StatusBar style="dark" />
          <Slot />
        </HouseholdProvider>
      </AuthProvider>
    </SafeAreaProvider>
  );
}
