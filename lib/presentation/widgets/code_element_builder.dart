import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';

import '../../l10n/app_localizations.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') {
      return null;
    }

    String language = 'plaintext';
    if (element.attributes['class'] != null) {
      String lg = element.attributes['class'] as String;
      if (lg.startsWith('language-')) {
        language = lg.substring(9);
      }
    }

    // When the code tag is inside a pre tag, it's a code block (multiline).
    // Otherwise, it's inline code. We can check if the text contains newlines, or use a heuristic.
    String textContent = element.textContent;
    bool isInline = !textContent.contains('\n') && (element.attributes['class'] == null);

    final colorScheme = Theme.of(context).colorScheme;

    if (isInline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          textContent,
          style: GoogleFonts.firaCode(
            fontSize: 13,
            color: colorScheme.primary,
          ),
        ),
      );
    }

    // Multiline code block
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282C34), // matches atom-one-dark background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E2227), // slightly darker than the code block
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFABB2BF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: textContent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.codeCopiedShort),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.copy, size: 14, color: Color(0xFFABB2BF)),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: Color(0xFFABB2BF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Code content
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: HighlightView(
                textContent.trimRight(), // remove trailing newline
                language: language,
                theme: atomOneDarkTheme,
                padding: EdgeInsets.zero,
                textStyle: GoogleFonts.firaCode(
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
