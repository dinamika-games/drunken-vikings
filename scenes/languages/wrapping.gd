class_name Wrapping
extends RefCounted

## Break a text into lines which fit a width, in every language: at the
## spaces, and in Chinese and Japanese, which write no spaces, between any two
## characters, but never before a closing mark (。、！？」) nor after an
## opening one (「（).

const _CLOSING := "。、，．・：；！？」』）】〕〉》ー…‥ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ々〜,.!?:;)]}%"
const _OPENING := "「『（【〔〈《([{"


## The pieces of the [param text] between which a line may break: Array of
## [the text of the piece, what joins it to the piece before on the same line
## (" " or "")].
static func pieces(text: String) -> Array:
    var result: Array = []
    var current := ""
    var glue := ""
    var pending_space := false
    for i in range(text.length()):
        var c := text[i]
        if c == " " or c == "\n" or c == "\t":
            if current != "":
                result.append([current, glue])
                current = ""
            pending_space = true
            continue
        var wide := _is_wide(c)
        if current != "" and _CLOSING.contains(c):
            current += c
            continue
        if current != "" and (wide or _is_wide(current[-1])) and not _OPENING.contains(current[-1]):
            result.append([current, glue])
            current = ""
            glue = ""
        if current == "":
            glue = " " if pending_space else ""
        current += c
        pending_space = false
    if current != "":
        result.append([current, glue])
    return result


## Break the [param text] into lines no wider than the [param width] (a piece
## wider than the width alone stays on a line of its own).
static func wrap(text: String, font: Font, font_size: int, width: float) -> Array[String]:
    var lines: Array[String] = []
    var current := ""
    for piece in pieces(text):
        var candidate: String = piece[0] if current == "" else current + piece[1] + piece[0]
        if (
            current != ""
            and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width
        ):
            lines.append(current)
            current = piece[0]
        else:
            current = candidate
    if current != "":
        lines.append(current)
    return lines


## Whether the character [param c] is written without spaces around it: a
## Chinese character, Japanese kana, or a full-width mark.
static func _is_wide(c: String) -> bool:
    var code := c.unicode_at(0)
    return (
        (code >= 0x3000 and code <= 0x30FF)
        or (code >= 0x3400 and code <= 0x4DBF)
        or (code >= 0x4E00 and code <= 0x9FFF)
        or (code >= 0xF900 and code <= 0xFAFF)
        or (code >= 0xFF00 and code <= 0xFFEF)
    )
