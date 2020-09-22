import 'package:aves/model/filters/album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/image_entry.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/image_file_service.dart';
import 'package:aves/utils/durations.dart';
import 'package:aves/widgets/common/action_delegates/feedback.dart';
import 'package:aves/widgets/common/action_delegates/permission_aware.dart';
import 'package:aves/widgets/common/action_delegates/rename_album_dialog.dart';
import 'package:aves/widgets/filter_grids/common/chip_actions.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:pedantic/pedantic.dart';

class ChipActionDelegate {
  Future<void> onActionSelected(BuildContext context, CollectionFilter filter, ChipAction action) async {
    // wait for the popup menu to hide before proceeding with the action
    await Future.delayed(Durations.popupMenuAnimation * timeDilation);

    switch (action) {
      case ChipAction.pin:
        final pinnedFilters = settings.pinnedFilters..add(filter);
        settings.pinnedFilters = pinnedFilters;
        break;
      case ChipAction.unpin:
        final pinnedFilters = settings.pinnedFilters..remove(filter);
        settings.pinnedFilters = pinnedFilters;
        break;
      default:
        break;
    }
  }
}

class AlbumChipActionDelegate extends ChipActionDelegate with FeedbackMixin, PermissionAwareMixin {
  final CollectionSource source;

  AlbumChipActionDelegate({
    @required this.source,
  });

  @override
  Future<void> onActionSelected(BuildContext context, CollectionFilter filter, ChipAction action) async {
    await super.onActionSelected(context, filter, action);
    switch (action) {
      case ChipAction.rename:
        unawaited(_showRenameDialog(context, filter as AlbumFilter));
        break;
      default:
        break;
    }
  }

  Future<void> _showRenameDialog(BuildContext context, AlbumFilter filter) async {
    final album = filter.album;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => RenameAlbumDialog(album),
    );
    if (newName == null || newName.isEmpty) return;

    if (!await checkStoragePermissionForAlbums(context, {album})) return;

    final result = await ImageFileService.renameDirectory(album, newName);
    final bySuccess = groupBy<Map, bool>(result, (fields) => fields['success']);

    final albumEntries = source.rawEntries.where(filter.filter);
    final movedEntries = <ImageEntry>[];
    await Future.forEach<Map>(bySuccess[true], (newFields) async {
      final oldContentId = newFields['oldContentId'];
      final entry = albumEntries.firstWhere((entry) => entry.contentId == oldContentId, orElse: () => null);
      if (entry != null) {
        movedEntries.add(entry);
        await source.moveEntry(entry, newFields);
      }
    });
    source.updateAfterMove(
      entries: movedEntries,
      fromAlbums: {album},
      toAlbum: path.join(path.dirname(album), newName),
      copy: false,
    );

    final failed = bySuccess[false]?.length ?? 0;
    if (failed > 0) {
      showFeedback(context, 'Failed to move ${Intl.plural(failed, one: '$failed item', other: '$failed items')}');
    } else {
      showFeedback(context, 'Done!');
    }
  }
}