import { requireNativeView } from 'expo';
import * as React from 'react';

import { ReactNativePcmPlayerViewProps } from './ReactNativePcmPlayer.types';

const NativeView: React.ComponentType<ReactNativePcmPlayerViewProps> =
  requireNativeView('ReactNativePcmPlayer');

export default function ReactNativePcmPlayerView(props: ReactNativePcmPlayerViewProps) {
  return <NativeView {...props} />;
}
