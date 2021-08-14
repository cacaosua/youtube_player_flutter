// Copyright 2020 Sarbagya Dhaubanjar. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:youtube_player_iframe/src/enums/youtube_error.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
// import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../controller.dart';
import '../enums/player_state.dart';
import '../meta_data.dart';

/// A youtube player widget which interacts with the underlying webview inorder to play YouTube videos.
///
/// Use [YoutubePlayerIFrame] instead.
class RawYoutubePlayer extends StatefulWidget {
  /// The [YoutubePlayerController].
  final YoutubePlayerController controller;

  /// Which gestures should be consumed by the youtube player.
  ///
  /// It is possible for other gesture recognizers to be competing with the player on pointer
  /// events, e.g if the player is inside a [ListView] the [ListView] will want to handle
  /// vertical drags. The player will claim gestures that are recognized by any of the
  /// recognizers on this list.
  ///
  /// By default vertical and horizontal gestures are absorbed by the player.
  /// Passing an empty set will ignore the defaults.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Creates a [RawYoutubePlayer] widget.
  const RawYoutubePlayer({
    Key? key,
    required this.controller,
    this.gestureRecognizers,
  }) : super(key: key);

  @override
  _MobileYoutubePlayerState createState() => _MobileYoutubePlayerState();
}

class _MobileYoutubePlayerState extends State<RawYoutubePlayer>
    with WidgetsBindingObserver {
  late final YoutubePlayerController controller;
  late final Completer<InAppWebViewController> _webController;
  PlayerState? _cachedPlayerState;
  bool _isPlayerReady = false;
  bool _onLoadStopCalled = false;

  @override
  void initState() {
    super.initState();
    _webController = Completer();
    controller = widget.controller;
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_cachedPlayerState != null &&
            _cachedPlayerState == PlayerState.playing) {
          controller.play();
        }
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        _cachedPlayerState = controller.value.playerState;
        controller.pause();
        break;
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      key: ValueKey(controller.hashCode),
      initialData: InAppWebViewInitialData(
        data: player,
        // baseUrl: Uri.parse(
        //   // controller.params.privacyEnhanced
        //   //     ? 'https://www.youtube-nocookie.com'
        //   //     : 'https://www.youtube.com',
        //   'www.dailymotion.com'
        // ),
        encoding: 'utf-8',
        mimeType: 'text/html',
      ),
      gestureRecognizers: widget.gestureRecognizers ??
          {
            Factory<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(),
            ),
            Factory<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(),
            ),
          },
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          userAgent: userAgent,
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          disableContextMenu: true,
          supportZoom: false,
          disableHorizontalScroll: false,
          disableVerticalScroll: false,
          useShouldOverrideUrlLoading: true,
        ),
        ios: IOSInAppWebViewOptions(
          allowsInlineMediaPlayback: true,
          allowsAirPlayForMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
        ),
        android: AndroidInAppWebViewOptions(
          useWideViewPort: false,
          useHybridComposition: controller.params.useHybridComposition,
        ),
      ),
      shouldOverrideUrlLoading: (_, detail) async {
        // final uri = detail.request.url;
        // if (uri == null) return NavigationActionPolicy.CANCEL;

        // final feature = uri.queryParameters['feature'];
        // if (feature == 'emb_rel_pause') {
        //   if (uri.queryParameters.containsKey('v')) {
        //     controller.load(uri.queryParameters['v']!);
        //   }
        // } else {
        //   url_launcher.launch(uri.toString());
        // }
        return NavigationActionPolicy.ALLOW;
      },
      onWebViewCreated: (webController) {
        if (!_webController.isCompleted) {
          _webController.complete(webController);
        }
        controller.invokeJavascript = _callMethod;
        _addHandlers(webController);
      },
      onLoadStop: (_, __) {
        _onLoadStopCalled = true;
        if (_isPlayerReady) {
          controller.add(
            controller.value.copyWith(isReady: true),
          );
        }
      },
      onConsoleMessage: (_, message) {
        log(message.message);
      },
      onEnterFullscreen: (_) => controller.onEnterFullscreen?.call(),
      onExitFullscreen: (_) => controller.onExitFullscreen?.call(),
    );
  }

  Future<void> _callMethod(String methodName) async {
    final webController = await _webController.future;
    webController.evaluateJavascript(source: methodName);
  }

  void _addHandlers(InAppWebViewController webController) {
    webController
      ..addJavaScriptHandler(
        handlerName: 'Ready',
        callback: (_) {
          print(111);
          _isPlayerReady = true;
          if (_onLoadStopCalled) {
            controller.add(
              controller.value.copyWith(isReady: true),
            );
          }
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'StateChange',
        callback: (args) {
          print(222);
          switch (args.first as int) {
            case -1:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.unStarted,
                  isReady: true,
                ),
              );
              break;
            case 0:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.ended,
                ),
              );
              break;
            case 1:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.playing,
                  hasPlayed: true,
                  error: YoutubeError.none,
                ),
              );
              break;
            case 2:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.paused,
                ),
              );
              break;
            case 3:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.buffering,
                ),
              );
              break;
            case 5:
              controller.add(
                controller.value.copyWith(
                  playerState: PlayerState.cued,
                ),
              );
              break;
            default:
              throw Exception("Invalid player state obtained.");
          }
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'PlaybackQualityChange',
        callback: (args) {
          print(333);
          controller.add(
            controller.value.copyWith(playbackQuality: args.first as String),
          );
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'PlaybackRateChange',
        callback: (args) {
          print(444);
          final num rate = args.first;
          controller.add(
            controller.value.copyWith(playbackRate: rate.toDouble()),
          );
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'Errors',
        callback: (args) {
          print(555);
          controller.add(
            controller.value.copyWith(error: errorEnum(args.first as int)),
          );
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'VideoData',
        callback: (args) {
          print(666);
          controller.add(
            controller.value
                .copyWith(metaData: YoutubeMetaData.fromRawData(args.first)),
          );
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'VideoTime',
        callback: (args) {
          print(777);
          final position = args.first * 1000;
          final num buffered = args.last;
          controller.add(
            controller.value.copyWith(
              position: Duration(milliseconds: position.floor()),
              buffered: buffered.toDouble(),
            ),
          );
        },
      );
  }

  String get player => '''
    <!DOCTYPE html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      </head>
    <body>
        <div 
          id="player-dailymotion"
          style="
            position:absolute; top:0px; 
            left:0px; bottom:0px; right:10px; 
            width:100%; height:100%; border:none; 
            margin:0; padding:0; overflow:hidden; 
            z-index:999999;
          "
        ></div>
        <script src="https://api.dmcdn.net/all.js"></script>
        <script>
        	let isFullScreen = false;
          setTimeout(function() {
            var player = DM.player(document.querySelector('#player-dailymotion'), {
              video: 'x831qo4',
              width: '100%',
              height: '100%',
              params: {
                autoplay: 1,
                logo: 0,
                controls: 1,
                mute: 1
              }
            });

            player.addEventListener('apiready', function(e) {
              console.log('api ready', e);
              
            });

            player.addEventListener('error', function(e) {
              console.log('error', e);
            });

            player.addEventListener('canplay', function(e) {
              console.log('canplay', e);
            });

            player.addEventListener('fullscreenchange', function(e) {
              if(isFullScreen != e.target.fullscreen) {
                isFullScreen = e.target.fullscreen;
                if(!isFullScreen) {
                  setTimeout(function() {
                    // player.contentWindow.postMessage('{"command":"pause","parameters":[]}', "*")
                    player.play();
                  }, 400);
                  
                }
              }
            });

            // player.addEventListener('progress', function(e) {
            //   console.log('progress', e);
            // });

            player.addEventListener('play', function(e) {
              console.log('ad_play', e);
              // player.setFullscreen(true);
            });

            player.addEventListener('end', function(e) {
              console.log('ad_end', e);
              // player.setFullscreen(false);
            });

            document.querySelector('#play').addEventListener('click', function() {
              console.log('click on play');
              player.play();
            });

            document.querySelector('#pause').addEventListener('click', function() {
              console.log('click on pause');
              player.pause();
            });

          }, 1000);
        </script>
    </body>
  ''';

  String get userAgent => !controller.params.desktopMode
      ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
      : '';
}


// <script>
//   console.log(111111);
//   $initPlayerIFrame
//   var player;
//   var timerId;
//   function onYouTubeIframeAPIReady() {
//       console.log(111111);
//       player = new YT.Player('player', {
//           events: {
//               onReady: function(event) { window.flutter_inappwebview.callHandler('Ready'); },
//               onStateChange: function(event) { sendPlayerStateChange(event.data); },
//               onPlaybackQualityChange: function(event) { window.flutter_inappwebview.callHandler('PlaybackQualityChange', event.data); },
//               onPlaybackRateChange: function(event) { window.flutter_inappwebview.callHandler('PlaybackRateChange', event.data); },
//               onError: function(error) { window.flutter_inappwebview.callHandler('Errors', error.data); }
//           },
//       });
//   }

//   function sendPlayerStateChange(playerState) {
//       clearTimeout(timerId);
//       window.flutter_inappwebview.callHandler('StateChange', playerState);
//       if (playerState == 1) {
//           startSendCurrentTimeInterval();
//           sendVideoData(player);
//       }
//   }

//   function sendVideoData(player) {
//       var videoData = {
//           'duration': player.getDuration(),
//           'title': player.getVideoData().title,
//           'author': player.getVideoData().author,
//           'videoId': player.getVideoData().video_id
//       };
//       window.flutter_inappwebview.callHandler('VideoData', videoData);
//   }

//   function startSendCurrentTimeInterval() {
//       timerId = setInterval(function () {
//           window.flutter_inappwebview.callHandler('VideoTime', player.getCurrentTime(), player.getVideoLoadedFraction());
//       }, 100);
//   }

//   $youtubeIFrameFunctions
// </script>