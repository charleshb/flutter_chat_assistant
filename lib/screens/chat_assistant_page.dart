import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:hive/hive.dart';

import '../controller/gen_ai_ctrl.dart';
import '../hive_model/chat_item.dart';
import '../hive_model/message_item.dart';
import '../hive_model/message_role.dart';

class ChatAssistantPage extends StatefulWidget {
  const ChatAssistantPage({super.key, required this.chatItem});

  final ChatItem chatItem;

  @override
  State<ChatAssistantPage> createState() => _ChatAssistantPageState();
}

class _ChatAssistantPageState extends State<ChatAssistantPage> {
  final List<types.Message> _messages = [];
  final List<HomeAssistantChatMessageModel> _aiMessages = [];
  late types.User ai;
  late types.User user;
  late Box messageBox;

  late String appBarTitle;

  var chatResponseId = '';
  var chatResponseContent = '';

  bool isAiTyping = false;
  final ChatController _chatCtrl =
      ChatController("https://apimgmtchatassistant.azure-api.net/home-builder-ai/score",
          "<<Subscription-Key>>",
          "",[]);

  @override
  void initState() {
    super.initState();
    ai = const types.User(id: 'ai', firstName: 'AI');
    user = const types.User(id: 'user', firstName: 'You');

    messageBox = Hive.box('messages');

    appBarTitle = widget.chatItem.title;

    // read chat history from Hive
    for (var messageItem in widget.chatItem.messages) {
      messageItem as MessageItem;
      // Add to chat view
      final textMessage = types.TextMessage(
        author: messageItem.role == MessageRole.ai ? ai : user,
        createdAt: messageItem.createdAt.millisecondsSinceEpoch,
        id: randomString(),
        text: messageItem.message,
      );

      _messages.insert(0, textMessage);

      // construct chatgpt messages
      _aiMessages.add(HomeAssistantChatMessageModel(
        chatInput: messageItem.message,
        chatHistory: []
      ));
    }
  }

  String randomString() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(255));
    return base64UrlEncode(values);
  }

  void _completeChat(String currentId, String prompt) async {
    _aiMessages.add(HomeAssistantChatMessageModel(
      chatInput: prompt,
      chatHistory: []
    ));

    Stream<HomeAssistantStreamChatCompletionModel> chatStream =
      _chatCtrl.postStream(
            to: currentId,
            onSuccess: (Map<String, dynamic> response, currentId) {
              debugPrint(response["chat_output"]);
              return HomeAssistantStreamChatCompletionModel(currentId, response["chat_output"]);
              },
            body: {
              "chat_input": _aiMessages.last.chatInput(),
              "chat_history": _aiMessages.last.chatHistory()
            }
        );

    // OpenAI.instance.chat.createStream(
    //   model: "gpt-3.5-turbo",
    //   messages: _aiMessages,
    // );

    chatStream.listen((chatStreamEvent) {
      //debugPrint(chatStreamEvent.toString());
      // existing id: just update to the same text bubble
      if (chatResponseId == chatStreamEvent.id) {
        chatResponseContent +=
            chatStreamEvent.responseText;
            //chatStreamEvent.choices.first ?? '';

        _addMessageStream(chatResponseContent);
        /*
        if (chatStreamEvent.choices.first.finishReason == "stop") {
          isAiTyping = false;
          _aiMessages.add(HomeAssistantChatMessageModel(
            chatInput: chatResponseContent,
            chatHistory: []
          ));
          _saveMessage(chatResponseContent, MessageRole.ai);
          chatResponseId = '';
          chatResponseContent = '';
        }*/
      } else {
        // new id: create new text bubble
        chatResponseId = chatStreamEvent.id;
        chatResponseContent = chatStreamEvent.responseText;//chatStreamEvent.choices.first ?? '';
        onMessageReceived(id: chatResponseId, message: chatResponseContent);
        //isAiTyping = true;
      }
    });
  }

  void onMessageReceived({String? id, required String message}) {
    var newMessage = types.TextMessage(
      author: ai,
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: message,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _addMessage(newMessage);
  }

  // add new bubble to chat
  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  /// Save message to Hive database
  void _saveMessage(String message, MessageRole role) {
    final messageItem = MessageItem(message, role, DateTime.now());
    messageBox.add(messageItem);
    widget.chatItem.messages.add(messageItem);
    widget.chatItem.save();
  }

  // modify last bubble in chat
  void _addMessageStream(String message) {
    setState(() {
      _messages.first =
          (_messages.first as types.TextMessage).copyWith(text: message);
    });
  }

  void _handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: message.text,
    );

    _addMessage(textMessage);
    _saveMessage(message.text, MessageRole.user);
    _completeChat(textMessage.id, message.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: Chat(
        typingIndicatorOptions: TypingIndicatorOptions(
          typingUsers: [if (isAiTyping) ai],
        ),
        inputOptions: InputOptions(enabled: !isAiTyping),
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: user,
        theme: DefaultChatTheme(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
