import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/skeletons.dart';

class ListLoadingState extends StatefulWidget {
  final Widget child;
  final String slowMessage;

  const ListLoadingState({
    super.key,
    required this.child,
    this.slowMessage = '网络有点慢，正在继续加载',
  });

  @override
  State<ListLoadingState> createState() => _ListLoadingStateState();
}

class _ListLoadingStateState extends State<ListLoadingState> {
  bool _showSlowMessage = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSlowMessage = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showSlowMessage)
          Positioned(
            left: KkSpacing.lg,
            right: KkSpacing.lg,
            bottom: KkSpacing.lg,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: KkColors.bgCard,
                borderRadius: BorderRadius.circular(KkRadius.pill),
                border: Border.all(color: KkColors.bd),
                boxShadow: KkElevation.card,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.md,
                  vertical: KkSpacing.sm,
                ),
                child: Text(
                  widget.slowMessage,
                  style: KkType.bodySm.copyWith(color: KkColors.t3),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ProjectListSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final int itemCount;

  const ProjectListSkeleton({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      KkSpacing.lg,
      KkSpacing.sm,
      KkSpacing.lg,
      KkSpacing.xxl,
    ),
    this.itemCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ListLoadingState(
      child: ListView.separated(
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.lg),
        itemBuilder: (_, __) => const ProjectCardSkeleton(),
      ),
    );
  }
}

class PostListSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final int itemCount;

  const PostListSkeleton({
    super.key,
    this.padding = const EdgeInsets.only(bottom: KkSpacing.xxl),
    this.itemCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ListLoadingState(
      child: ListView.builder(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (_, __) => const PostCardSkeleton(),
      ),
    );
  }
}

class CompactListSkeleton extends StatelessWidget {
  final int itemCount;

  const CompactListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListLoadingState(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: KkSpacing.sm),
        itemCount: itemCount,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: KkColors.bd),
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.md,
          ),
          child: Row(
            children: [
              SkeletonBox(width: 36, height: 36),
              SizedBox(width: KkSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 180, height: 14),
                    SizedBox(height: KkSpacing.sm),
                    SkeletonLine(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
