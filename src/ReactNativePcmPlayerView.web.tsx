import * as React from 'react';

import { ReactNativePcmPlayerViewProps } from './ReactNativePcmPlayer.types';

export default function ReactNativePcmPlayerView(props: ReactNativePcmPlayerViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
