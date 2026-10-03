import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart'
    show setPasswordDialog;

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
  bool _passwordSet = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final id = await bind.mainGetMyId();
    final set = (await bind.mainGetCommon(key: "permanent-password-set")) ==
        "true";
    if (mounted) {
      setState(() {
        _id = id;
        _passwordSet = set;
      });
    }
  }

  String get _formattedId =>
      _id.replaceAllMapped(RegExp(r'.{3}'), (m) => '${m[0]} ').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(translate('ID'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        SelectableText(_formattedId,
            style: theme.textTheme.headlineMedium
                ?.copyWith(color: MyTheme.idColor, letterSpacing: 2)),
        const SizedBox(height: 24),
        Text(translate('Password'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(_passwordSet
                ? translate('Permanent password is set')
                : translate('No password set')),
          ),
          TextButton(
            onPressed: () => setPasswordDialog(notEmptyCallback: _refresh),
            child: Text(translate('Set permanent password')),
          ),
        ]),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.mobile_screen_share),
          label: Text(translate('Start sharing')),
          style: FilledButton.styleFrom(
              backgroundColor: MyTheme.accent,
              minimumSize: const Size.fromHeight(52)),
          onPressed: _passwordSet
              ? () => iosBroadcastChannel.invokeMethod('start')
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          translate('VITA can see your screen while sharing is on, but cannot control it. Stop sharing from the red bar or Control Centre.'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
