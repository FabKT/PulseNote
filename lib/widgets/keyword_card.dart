import 'package:flutter/material.dart';
import '../models/keyword_model.dart';
import '../ui/app_theme.dart';

// Carte affichée dans la liste des mots-clés.
class KeywordCard extends StatelessWidget {
  final KeywordModel keyword;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const KeywordCard({
    super.key,
    required this.keyword,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.panel(radius: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
          child: const Icon(Icons.record_voice_over,
              color: AppTheme.primary, size: 20),
        ),
        title: Text(
          '"${keyword.text}"',
          style: const TextStyle(
              color: AppTheme.text, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6, top: 2),
            decoration: BoxDecoration(
              color: keyword.isRecorded ? AppTheme.primary : AppTheme.danger,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            keyword.isRecorded ? 'Échantillon enregistré' : 'Aucun échantillon',
            style: TextStyle(
                color: keyword.isRecorded ? AppTheme.primary : AppTheme.danger,
                fontSize: 12),
          ),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: AppTheme.primary, size: 20),
              onPressed: onEdit,
              tooltip: 'Modifier',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.danger, size: 20),
              onPressed: onDelete,
              tooltip: 'Supprimer',
            ),
          ],
        ),
      ),
    );
  }
}
