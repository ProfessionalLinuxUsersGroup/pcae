#!/bin/bash
# To be run in the project's root directory
declare RESOURCES_FILE='./src/resources.md'
declare SEARCH_DIR="./src"
declare FILE_PATTERN="*.md"
declare -A ADDED_LINKS

declare -a FILES
IFS=$'\n' read -r -d '' -a FILES < <(find "$SEARCH_DIR" -maxdepth 1 -mindepth 1 -name "$FILE_PATTERN")

debug() {
    printf "[ \033[33mDEBUG\033[0m ]: "
    printf "%s\n" "$*"
}

pull-links() {
    local -i COUNT_MD_LINKS=0
    local -i COUNT_REG_LINKS=0
    local -i COUNT_UF_LINKS=0
    local -i DUPLICATES
    for FILE in "${FILES[@]}"; do
        local UNIT=
        [[ "$FILE" == *resources.md ]] && continue  
        [[ "$FILE" == *unitindex.md ]] && continue  

        declare -a RESOURCES

        IFS=$'\n' read -r -d '' -a RESOURCES < <(
            grep -i -E '\<https://' "$FILE" |
                grep -v -E '(img)? ?src=|discord\.(gg|com)|user-attachments'
        )

        for RESOURCE in "${RESOURCES[@]}"; do
            local RESOURCE
            local MARKDOWN_LINK=
            [[ $FILE =~ .*u([0-9]+).*\.md ]] && UNIT="${BASH_REMATCH[1]}"

            # extract markdown link from the line
            MARKDOWN_LINK="$(printf "%s" "$RESOURCE" | perl -pe 's/.*(\[.*?\]\(.*?\)).*/\1/')" 

            if [[ $MARKDOWN_LINK =~ .*(<.*>).* ]]; then
                # Link is formatted as: <http://example.com>
                MARKDOWN_LINK="${BASH_REMATCH[1]}"
                COUNT_REG_LINKS+=1
            elif [[ $MARKDOWN_LINK =~ .*[^[\<\(](https://[^ \)]+).* ]]; then
                # Link is unformatted: http://example.com
                MARKDOWN_LINK="${BASH_REMATCH[1]}"
                COUNT_UF_LINKS+=1
                continue
            else
                # Link is formatted as: [Link](http://example.com)
                COUNT_MD_LINKS+=1
            fi
            [[ -z $MARKDOWN_LINK ]] && continue

            # Fix duplicate problem
            # Using grep to check for duplicates created a race condition
            # - Add associative array containing links already added
            #   - Bash can't parse markdown links as associative array keys
            #   - use md5sum hashes
            LINK_HASH=$(
                printf "%s" "${MARKDOWN_LINK,,}" |
                    sed -E 's/\/([>\)])?$/\1/' |
                    md5sum |
                    cut -d ' ' -f1
            )

            if [[ -z "${ADDED_LINKS["$LINK_HASH"]}" ]]; then
                [[ -n $UNIT ]] && sed -i "/^## Unit $UNIT\>/a- $MARKDOWN_LINK" "$RESOURCES_FILE"
                [[ -z $UNIT ]] && sed -i "/^## Misc$/a- $MARKDOWN_LINK" "$RESOURCES_FILE"
                ADDED_LINKS["$LINK_HASH"]=1
            else
                debug "Duplicate link found, skipping: ${MARKDOWN_LINK}"
                (( DUPLICATES++ ))
            fi

        done

    done

    TOTAL_LINK_COUNT=$(( COUNT_MD_LINKS + COUNT_UF_LINKS + COUNT_REG_LINKS ))
    cat <<- EOF
	REPORT:
	- Markdown Links        $COUNT_MD_LINKS
	- Regular Links         $COUNT_REG_LINKS
	- Unformatted Links     $COUNT_UF_LINKS
	Total Links: $TOTAL_LINK_COUNT
	Total links added: ${#ADDED_LINKS[@]}
	
	Duplicates: $DUPLICATES
	EOF

}

format-resources() {
    # truncate file
    : > "$RESOURCES_FILE"
    cat <<- EOF >> "$RESOURCES_FILE"
	<div class="flex-container">
	        <img src="https://github.com/ProfessionalLinuxUsersGroup/img/blob/main/Assets/Logos/ProLUG_Round_Transparent_LOGO.png?raw=true" width="64" height="64"></img>
	    <p>
	        <h1>Course Resources</h1>
	    </p>
	</div>
	This is a comprehensive list of all external resources used in this course.

	EOF

    if [[ -f ./src/unitindex.md ]]; then
        perl -ne 'print "## Unit $1 - $2\n\n" if s/^[|]\s*(\d+)\s*[|]\s*[[](.*?)[]].*$/\1 \2/' < src/unitindex.md |
            tee -a "$RESOURCES_FILE" > /dev/null
    else
        for i in {1..16}; do
            printf "## Unit %s\n\n" "$i" >> "$RESOURCES_FILE"
        done
    fi

    if ! grep -qi -E "^## Misc$" "$RESOURCES_FILE"; then
        printf "## Misc\n" >> $RESOURCES_FILE
    fi

}

format-resources
pull-links
