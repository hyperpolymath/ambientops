# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Import AceText .atc (XML) files to comment-bank.scm format.
# Pure Julia — no Python dependency.

using Dates

function escape_scm(s::String)
    s = replace(s, "\\" => "\\\\")
    s = replace(s, "\"" => "\\\"")
    s = replace(s, "\r\n" => "\\n")
    s = replace(s, "\r" => "\\n")
    s = replace(s, "\n" => "\\n")
    return s
end

function import_acetext(input_path::String, output_path::String="imported-comments.scm")
    if !isfile(input_path)
        println(stderr, "Error: file not found: $input_path")
        return 1
    end

    content = read(input_path, String)

    m = match(r"collection[^>]*label=\"([^\"]*)\"", content)
    collection_name = m !== nothing ? m.captures[1] : "unknown"

    text_pattern = r"<(?:\w+:)?text[^>]*>([\s\S]*?)</(?:\w+:)?text>"
    clips = String[]
    for m in eachmatch(text_pattern, content)
        text = strip(m.captures[1])
        text = replace(text, "&amp;" => "&", "&lt;" => "<", "&gt;" => ">",
                        "&quot;" => "\"", "&#39;" => "'")
        length(text) > 10 && push!(clips, text)
    end

    println("Importing: $collection_name")
    println("Clips found: $(length(clips))")

    today = Dates.format(Dates.today(), "yyyy-mm-dd")

    open(output_path, "w") do io
        println(io, ";; SPDX-License-Identifier: PMPL-1.0-or-later")
        println(io, ";; Imported from AceText: $collection_name")
        println(io, ";; Date: $today")
        println(io, ";; Source: $input_path")
        println(io)
        println(io, "(comment-collection")
        println(io, "  (metadata")
        println(io, "    (source \"acetext\")")
        println(io, "    (original-name \"$(escape_scm(collection_name))\")")
        println(io, "    (imported \"$today\")")
        println(io, "    (clip-count $(length(clips))))")
        println(io)
        println(io, "  (category \"imported\"")
        for (i, clip) in enumerate(clips)
            escaped = escape_scm(clip)
            length(escaped) > 500 && (escaped = escaped[1:500] * "...")
            println(io, "    (comment (id \"imp-$(lpad(string(i), 4, '0'))\")")
            println(io, "      (text \"$escaped\"))")
        end
        println(io, "  )")
        println(io, ")")
    end

    println("Output: $output_path")
    println("Total imported: $(length(clips)) clips")
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    if isempty(ARGS)
        println("Usage: julia import-acetext.jl <file.atc> [output.scm]")
        exit(1)
    end
    exit(import_acetext(ARGS[1], length(ARGS) >= 2 ? ARGS[2] : "imported-comments.scm"))
end
