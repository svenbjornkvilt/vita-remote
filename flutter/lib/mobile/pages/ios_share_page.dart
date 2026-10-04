import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

const iosBroadcastChannel = MethodChannel('fo.vita.remote/broadcast');

/// iOS can only share its screen through a ReplayKit broadcast, so this page
/// shows the ID and starts the broadcast extension, which runs the server.
class IosSharePage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Share screen");

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = <Widget>[];

  IosSharePage({Key? key}) : super(key: key);

  @override
  State<IosSharePage> createState() => _IosSharePageState();
}

class _IosSharePageState extends State<IosSharePage> {
  String _id = '';

  @override
  void initState() {
    super.initState();
    bind.mainGetMyId().then((id) {
      if (mounted) setState(() => _id = id);
    });
  }

  String _group(String s) =>
      s.replaceAllMapped(RegExp(r'.{3}'), (m) => '${m[0]} ').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final big = theme.textTheme.headlineMedium
        ?.copyWith(color: MyTheme.idColor, letterSpacing: 2);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(translate('ID'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        SelectableText(_group(_id), style: big),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.mobile_screen_share),
          label: Text(translate('Start sharing')),
          style: FilledButton.styleFrom(
              backgroundColor: MyTheme.accent,
              minimumSize: const Size.fromHeight(52)),
          onPressed: () => iosBroadcastChannel.invokeMethod('start'),
        ),
        const SizedBox(height: 16),
        Text(
          translate('Tap Start sharing and give VITA your ID.'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          translate('VITA can see your screen while sharing is on, but cannot control it. Stop sharing from the red bar or Control Centre.'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
