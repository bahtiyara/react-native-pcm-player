export type ReactNativePcmPlayerModuleEvents = {
  onMessage: (params: LogEventPayload) => void;
  onStatus: (params: StatusEventPayload) => void;
};

type LogEventPayload = {
  message: string;
};

type StatusEventPayload = {
  status: "listening";
};
