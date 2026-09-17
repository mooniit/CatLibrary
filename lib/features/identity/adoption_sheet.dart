import 'package:flutter/material.dart';

class AdoptionSheet extends StatefulWidget {
  const AdoptionSheet({super.key, required this.cats, required this.onAdopted});
  final Map<String, String> cats;
  final VoidCallback onAdopted;
  @override
  State<AdoptionSheet> createState() => _AdoptionSheetState();
}

class _AdoptionSheetState extends State<AdoptionSheet> {
  final name = TextEditingController();
  String kind = '黑色短毛猫';
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('认识新伙伴', style: Theme.of(context).textTheme.headlineSmall),
            const Text('免费领养 · 主人：本人（原型身份）\n仅本次运行有效；不创建真实家庭或猫咪。'),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: kind,
              items: [
                for (final k in ['黑色短毛猫', '浅色长毛猫'])
                  DropdownMenuItem(value: k, child: Text(k)),
              ],
              onChanged: (v) => kind = v!,
            ),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: '给猫咪起个名字',
                errorText: error,
              ),
            ),
            const SizedBox(height: 16),
            const Text('性格由你后续补充。家庭重名与多人并发校验将在 M1 由云端实现。'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final value = name.text.trim();
                setState(
                  () => error = value.isEmpty
                      ? '请填写名字'
                      : widget.cats.containsKey(kind)
                      ? '本人不能重复领养同一外观'
                      : widget.cats.values.contains(value)
                      ? '这个名字已在原型中使用'
                      : widget.cats.length >= 2
                      ? '本人最多两只猫'
                      : null,
                );
                if (error != null) return;
                widget.cats[kind] = value;
                widget.onAdopted();
                Navigator.pop(context);
              },
              child: const Text('试领养'),
            ),
          ],
        ),
      ),
    ),
  );
}
