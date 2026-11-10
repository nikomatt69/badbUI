import { Tabs } from "expo-router"
import { useFonts } from "expo-font"
import { Cinzel_500Medium } from "@expo-google-fonts/cinzel/500Medium"
import { IBMPlexSans_400Regular } from "@expo-google-fonts/ibm-plex-sans/400Regular"
import { StatusBar } from "expo-status-bar"
import { Text } from "react-native"
import { SessionProvider } from "../src/session"
import { colors } from "../src/ui"
export default function Layout() {
  const [loaded, error] = useFonts({ Cinzel: Cinzel_500Medium, Plex: IBMPlexSans_400Regular })
  if (!loaded && !error) return null
  return (
    <SessionProvider>
      <StatusBar style="light" />
      <Tabs
        screenOptions={{
          headerStyle: { backgroundColor: colors.bg },
          headerTintColor: colors.gold,
          headerTitleStyle: { fontFamily: "Cinzel" },
          tabBarStyle: { backgroundColor: colors.bg, borderTopColor: colors.line },
          tabBarActiveTintColor: colors.accent,
          tabBarInactiveTintColor: colors.muted,
        }}
      >
        <Tabs.Screen
          name="index"
          options={{
            title: "Fratelli di Azeroth",
            tabBarLabel: "Gilda",
            tabBarIcon: ({ color }) => <Text style={{ color }}>ᚠ</Text>,
          }}
        />
        <Tabs.Screen
          name="raid"
          options={{
            title: "Calendario raid",
            tabBarLabel: "Raid",
            tabBarIcon: ({ color }) => <Text style={{ color }}>⚔</Text>,
          }}
        />
        <Tabs.Screen
          name="availability"
          options={{
            title: "Disponibilità",
            tabBarLabel: "Chi c’è",
            tabBarIcon: ({ color }) => <Text style={{ color }}>◷</Text>,
          }}
        />
        <Tabs.Screen
          name="armory"
          options={{
            title: "Armory Forever",
            tabBarLabel: "Armory",
            tabBarIcon: ({ color }) => <Text style={{ color }}>✦</Text>,
          }}
        />
        <Tabs.Screen
          name="profile"
          options={{
            title: "Il tuo profilo",
            tabBarLabel: "Profilo",
            tabBarIcon: ({ color }) => <Text style={{ color }}>⌂</Text>,
          }}
        />
      </Tabs>
    </SessionProvider>
  )
}
