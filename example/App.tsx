import { useEvent } from "expo"
import ReactNativePcmPlayer from "react-native-pcm-player"
import { SafeAreaView, ScrollView, Text, View } from "react-native"
import { useEffect } from "react"

export default function App() {
	const { status } = useEvent(ReactNativePcmPlayer, "onStatus") ?? {}

	useEffect(() => {
		// Example usage with default sample rate (24000)
		ReactNativePcmPlayer.enqueuePcm("asdf")

		// Example usage with custom sample rate
		// ReactNativePcmPlayer.enqueuePcm("asdf", 44100);
	}, [])

	return (
		<SafeAreaView style={styles.container}>
			<ScrollView style={styles.container}>
				<Text style={styles.header}>Module API Example</Text>
				<Group name="Events">
					<Text>{status}</Text>
				</Group>
			</ScrollView>
		</SafeAreaView>
	)
}

function Group(props: { name: string; children: React.ReactNode }) {
	return (
		<View style={styles.group}>
			<Text style={styles.groupHeader}>{props.name}</Text>
			{props.children}
		</View>
	)
}

const styles = {
	header: {
		fontSize: 30,
		margin: 20,
	},
	groupHeader: {
		fontSize: 20,
		marginBottom: 20,
	},
	group: {
		margin: 20,
		backgroundColor: "#fff",
		borderRadius: 10,
		padding: 20,
	},
	container: {
		flex: 1,
		backgroundColor: "#eee",
	},
	view: {
		flex: 1,
		height: 200,
	},
}
