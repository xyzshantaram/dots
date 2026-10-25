function shrinkpdf
    argparse 'r/replace' 'h/help' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: shrinkpdf [OPTIONS] INPUT.pdf"
        echo
        echo "Shrink a PDF using Ghostscript."
        echo
        echo "Options:"
        echo "  -r, --replace    Replace the original PDF after successful conversion"
        echo "  -h, --help       Show this help message"
        return 0
    end

    if test (count $argv) -ne 1
        echo "Usage: shrinkpdf [OPTIONS] INPUT.pdf" >&2
        return 2
    end

    set input $argv[1]

    if not test -f "$input"
        echo "shrinkpdf: file not found: $input" >&2
        return 1
    end

    if not string match -qr '\.pdf$' -- "$input"
        echo "shrinkpdf: input must be a PDF: $input" >&2
        return 1
    end

    set output (string replace -r '\.pdf$' ' (shrunk).pdf' -- "$input")

    if test "$output" = "$input"
        echo "shrinkpdf: output file is the same as input" >&2
        return 1
    end

    gs \
        -sDEVICE=pdfwrite \
        -dCompatibilityLevel=1.4 \
        -dPDFSETTINGS=/prepress \
        -dNOPAUSE \
        -dQUIET \
        -dBATCH \
        -sOutputFile="$output" \
        "$input"

    if test $status -ne 0
        echo "shrinkpdf: Ghostscript failed; original file was not changed" >&2
        return 1
    end

    if set -q _flag_replace
        command rm -- "$input"
    end

    echo "$output"
end
