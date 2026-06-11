class NetworkCounterSample {
  const NetworkCounterSample({
    required this.timestamp,
    required this.bytesRecv,
    required this.bytesSent,
  });

  final DateTime timestamp;
  final int bytesRecv;
  final int bytesSent;
}

class NetworkThroughput {
  const NetworkThroughput({
    required this.receiveBytesPerSecond,
    required this.sendBytesPerSecond,
  });

  static const zero = NetworkThroughput(
    receiveBytesPerSecond: 0,
    sendBytesPerSecond: 0,
  );

  final double receiveBytesPerSecond;
  final double sendBytesPerSecond;
}

NetworkThroughput calculateThroughput({
  required NetworkCounterSample? previous,
  required NetworkCounterSample current,
  Duration maxElapsed = const Duration(minutes: 5),
}) {
  if (previous == null) {
    return NetworkThroughput.zero;
  }
  final elapsedMs = current.timestamp
      .difference(previous.timestamp)
      .inMilliseconds;
  if (elapsedMs <= 0 || elapsedMs > maxElapsed.inMilliseconds) {
    return NetworkThroughput.zero;
  }
  final recvDelta = current.bytesRecv - previous.bytesRecv;
  final sentDelta = current.bytesSent - previous.bytesSent;
  if (recvDelta < 0 || sentDelta < 0) {
    return NetworkThroughput.zero;
  }
  final elapsedSeconds = elapsedMs / 1000.0;
  return NetworkThroughput(
    receiveBytesPerSecond: recvDelta / elapsedSeconds,
    sendBytesPerSecond: sentDelta / elapsedSeconds,
  );
}
