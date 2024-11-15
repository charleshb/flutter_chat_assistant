import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
//import 'package:hive/hive.dart';
import 'package:fetch_client/fetch_client.dart' as fetch;

import '../request_failure.dart';
import '../chat_event_sink.dart';

const _DATA_START = "data: ";
const _DATA_DONE = "[DONError: Dart library 'dart:js_util' is not available on this platform.E]";

fetch.FetchClient createClient() =>
    fetch.FetchClient(mode: fetch.RequestMode.cors,
        // credentials: fetch.RequestCredentials.omit
        // streamRequests: true,
         referrerPolicy: fetch.RequestReferrerPolicy.origin
    );
const LineSplitter _chatStreamLineSplitter =
                          const OpenAIChatStreamLineSplitter();


class ChatController {
  ChatController(String apiUrl, String apiKey, String deploymentId, List<types.Message> chatMessages) {
    // DONE: implement ChatController
    _apiUrl = apiUrl;
    _apiKey = apiKey;
    _deploymentId = deploymentId;
    _chatMessages = chatMessages;
  }

  List<types.Message> _chatMessages = [];
  String _apiKey = "";
  String _apiUrl = "";
  String _deploymentId = "";

  String apiKey() => _apiKey;
  String apiUrl() => _apiUrl;
  String deploymentId() => _deploymentId;
  List<types.Message> ChatMessages() => _chatMessages;

  Stream<T> postStream<T>({
    required String to,
    required T Function(Map<String, dynamic>, String) onSuccess,
    required Map<String, dynamic> body,
  }) {
    StreamController<T> controller = StreamController<T>();

    final http.Client client = createClient();
    http.Request request = http.Request(
      "POST",
      Uri.parse(_apiUrl),
    );
    request.headers.addAll(buildHeaders(_apiKey, false, "", _deploymentId));
    request.body = jsonEncode(body);

    void close() {
      client.close();
      controller.close();
    }

    //OpenAILogger.log("starting request to $to");
    client.send(request).then(
          (respond) {
        //OpenAILogger.log("Starting to reading stream response");

        final stream = respond.stream
            .transform(utf8.decoder)
            .transform(_chatStreamLineSplitter);

        stream.listen(
              (value) {
            final data = value;

            final List<String> dataLines = data
                .split("\n")
                .where((element) => element.isNotEmpty)
                .toList();

            for (String line in dataLines) {
              if (line.startsWith(_DATA_START)) {
                final String data = line.substring(6);
                if (data.contains(_DATA_DONE)) {
                  //OpenAILogger.log("stream response is done");

                  return;
                }

                final decoded = jsonDecode(data) as Map<String, dynamic>;

                controller.add(onSuccess(decoded, to));

                continue;
              }
              final error = jsonDecode(data)['error'];
              if (error != null) {
                controller.addError(RequestFailedException(
                  error["message"],
                  respond.statusCode,
                ));
              }
            }
          },
          onDone: () {
            close();
          },
          onError: (error, stackTrace) {
            controller.addError(error, stackTrace);
          },
        );
      },
      onError: (error, stackTrace) {
        controller.addError(error, stackTrace);
      },
    );

    return controller.stream;
  }

  /// {@macro headers_builder}
  ///
  /// it will return a [Map<String, String>].
  ///
  /// if the [organization] is set, it will be added to the headers as well.
  /// If in anyhow the API key is not set, it will throw an [AssertionError] while debugging.
  // @internal
  static Map<String, String> buildHeaders(apiKey, isOrganizationSet, organization, deploymentId) {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json'
      //,'Accept': 'text/event-stream'
      // this changes for every deployment
      //,'azureml-model-deployment': deploymentId
    };

    assert(
    apiKey != null,
    """
      You must set the API key before making building any headers for a request.""",
    );

/*    if (isOrganizationSet) {
      headers['OpenAI-Organization'] = organization!;
    }*/

    headers["Ocp-Apim-Subscription-Key"] = "$apiKey";

    return headers;
  }

}


class HomeAssistantChatMessageModel {
  HomeAssistantChatMessageModel({required String chatInput, required List<String> chatHistory})
  {
    _chatInput = chatInput;
    _chatHistory = chatHistory;
  }

  String _chatInput = "";
  List<String> _chatHistory = [];

  String chatInput() => _chatInput;
  List<String> chatHistory() => _chatHistory;
}

class HomeAssistantStreamChatCompletionModel {
  HomeAssistantStreamChatCompletionModel(currentId, chat_output_text) {
    id = currentId;
    responseText = chat_output_text;
  }
  String id = "";
  List<String> choices = [];
  late String responseText;

}