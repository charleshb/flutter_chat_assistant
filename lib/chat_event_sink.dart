import 'dart:async';
import 'dart:convert';

const _DATA_START = "data: ";
const _DATA_DONE = "[DONE]";

/// Handling exceptions returned by OpenAI Stream API.
class OpenAIChatStreamSink extends EventSink<String> {
  final EventSink<String> _sink;

  final List<String> _carries = [];

  OpenAIChatStreamSink(this._sink);

  void add(String str) {
    if (str.startsWith(_DATA_START) || str.contains(_DATA_DONE)) {
      addCarryIfNeeded();

      _sink.add(str);
    } else {
      _carries.add(str);
    }
  }

  void addError(Object error, [StackTrace? stackTrace]) {
    _sink.addError(error, stackTrace);
  }

  void addSlice(String str, int start, int end, bool isLast) {
    if (start == 0 && end == str.length) {
      add(str);
    } else {
      add(str.substring(start, end));
    }
    if (isLast) close();
  }

  void addCarryIfNeeded() {
    if (_carries.isNotEmpty) {
      _sink.add(_carries.join());

      _carries.clear();
    }
  }

  void close() {
    addCarryIfNeeded();
    _sink.close();
  }
}

class OpenAIChatStreamLineSplitter extends LineSplitter {
  const OpenAIChatStreamLineSplitter();

  Stream<String> bind(Stream<String> stream) {
    Stream<String> lineStream = super.bind(stream);

    return Stream<String>.eventTransformed(
        lineStream, (sink) => OpenAIChatStreamSink(sink));
  }
}
