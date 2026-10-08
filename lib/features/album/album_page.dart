import 'package:flutter/material.dart';
import '../travel/travel_repository.dart';
import '../travel/travel_sheet.dart';
import '../identity/identity_repository.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.repository, this.onWallet});
  final TravelRepository repository;
  final ValueChanged<IdentityWallet>? onWallet;
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Map<String, dynamic>? data;
  bool busy = true, offline = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = await widget.repository.load(album: true);
      if (mounted) {
        setState(() {
          data = raw;
          offline = false;
        });
      }
    } catch (_) {
      final cached = await widget.repository.cached(album: true);
      if (mounted) {
        setState(() {
          data ??= cached;
          offline = true;
          error = '连接暂未确认，请刷新获取最新回忆。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = data?['photos'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('小屋相册'),
        actions: [
          IconButton(
            tooltip: '刷新相册',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Text(
                    '一起收藏的远方',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${photos.length} 条旅行回忆${offline ? ' · 离线记录' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null)
                    Text(error!, key: const Key('album-error')),
                  if (photos.isEmpty && !busy) ...[
                    const SizedBox(height: 60),
                    const Center(
                      child: Icon(Icons.markunread_mailbox_outlined, size: 48),
                    ),
                    const SizedBox(height: 20),
                    const Center(child: Text('第一次旅行，带回第一份回忆。')),
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton.icon(
                        onPressed: offline || data?['family_id'] == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => TravelSheet(
                                      repository: widget.repository,
                                      onWallet: widget.onWallet,
                                    ),
                                  ),
                                );
                                if (mounted) await load();
                              },
                        icon: const Icon(Icons.flight_takeoff_outlined),
                        label: const Text('安排旅行'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((c, index) {
                final photo = Map<String, dynamic>.from(photos[index]);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('photo-${photo['id']}'),
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute<void>(
                        builder: (_) => PhotoDetail(photo: photo),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: TravelRecordArt(photo: photo)),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                photo['destination_label'],
                                style: Theme.of(c).textTheme.titleMedium,
                              ),
                              Text(
                                photo['cat_name'],
                                style: Theme.of(c).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }, childCount: photos.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .85,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class TravelRecordArt extends StatelessWidget {
  const TravelRecordArt({super.key, required this.photo});
  final Map<String, dynamic> photo;
  static const _assets = {
    'black_short:palace': 'assets/images/travel/calico-palace-v1.png',
    'light_long:palace': 'assets/images/travel/longhair-palace-v1.png',
    'black_short:louvre': 'assets/images/travel/calico-louvre-v1.png',
    'light_long:louvre': 'assets/images/travel/longhair-louvre-v1.png',
    'black_short:fuji': 'assets/images/travel/calico-fuji-v1.png',
    'light_long:fuji': 'assets/images/travel/longhair-fuji-v1.png',
  };
  @override
  Widget build(BuildContext context) {
    final asset = _assets['${photo['appearance']}:${photo['destination']}'];
    if (asset != null) {
      return Semantics(
        label: '${photo['cat_name']}的${photo['destination_label']}旅行插画',
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: LayoutBuilder(
            builder: (context, constraints) => Image.asset(
              asset,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
              cacheWidth:
                  (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(200, 900),
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : Center(
                      child: Semantics(
                        label: '旅行插画加载中',
                        child: Icon(
                          Icons.photo_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
              errorBuilder: (_, _, _) => _pending(context),
            ),
          ),
        ),
      );
    }
    return _pending(context);
  }

  Widget _pending(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Semantics(
      label: '${photo['cat_name']}的${photo['destination_label']}旅行记录，插画待收录',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pets_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text('旅行插画待收录', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class PhotoDetail extends StatelessWidget {
  const PhotoDetail({super.key, required this.photo});
  final Map<String, dynamic> photo;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(
      photo['taken_at'],
    ).toUtc().add(const Duration(hours: 8));
    return Scaffold(
      appBar: AppBar(title: Text(photo['destination_label'])),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 1.5,
              child: TravelRecordArt(photo: photo),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            photo['cat_name'],
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(photo['destination_label']),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text('${date.year} 年 ${date.month} 月 ${date.day} 日'),
            subtitle: const Text('北京时间 · 返程日期'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text('安排人：${photo['arranger_label']}'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(photo['souvenir_label']),
            subtitle: const Text('已收入家庭库存，可回小屋布置。'),
          ),
        ],
      ),
    );
  }
}
