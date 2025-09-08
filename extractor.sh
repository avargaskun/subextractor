#!/bin/bash

# Script to extract ASS subtitles from MKV files and convert them to SRT
# Usage: ./extract_ass_to_srt.sh [file or directory]
# If no path is specified, uses the current directory.
# If a file is specified, it will process only that file.
# If a directory is specified, it will search for MKV files within it.

# Set the path to search (default to current directory if not specified)
SEARCH_PATH="${1:-.}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    if ! command -v mkvinfo &> /dev/null; then
        missing_deps+=("mkvtoolnix")
    fi
    
    if ! command -v ffmpeg &> /dev/null; then
        missing_deps+=("ffmpeg")
    fi
    
    if ! command -v ffprobe &> /dev/null; then
        missing_deps+=("ffprobe (usually comes with ffmpeg)")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies:${NC}"
        printf '%s\n' "${missing_deps[@]}"
        echo -e "${YELLOW}Please install them before running this script.${NC}"
        exit 1
    fi
}

# Function to check if file is accessible and not corrupted
validate_mkv_file() {
    local mkv_file="$1"
    
    # Check if file exists and is readable
    if [ ! -f "$mkv_file" ]; then
        echo -e "  ${RED}✗${NC} File does not exist: $mkv_file"
        return 1
    fi
    
    if [ ! -r "$mkv_file" ]; then
        echo -e "  ${RED}✗${NC} File is not readable: $mkv_file"
        return 1
    fi
    
    # Check if file is empty
    if [ ! -s "$mkv_file" ]; then
        echo -e "  ${RED}✗${NC} File is empty: $mkv_file"
        return 1
    fi
    
    # Quick validation that ffprobe can read the file
    if ! ffprobe -v error -show_format "$mkv_file" >/dev/null 2>&1; then
        echo -e "  ${RED}✗${NC} File appears to be corrupted or not a valid media file: $mkv_file"
        return 1
    fi
    
    return 0
}

# Function to check if MKV has ASS subtitles
has_ass_subtitles() {
    local mkv_file="$1"
    local temp_output
    local exit_code
    
    # Validate file first
    if ! validate_mkv_file "$mkv_file"; then
        return 1
    fi
    
    # Use ffprobe to check for ASS/SSA subtitles with proper error handling
    temp_output=$(ffprobe -v error -select_streams s -show_entries stream=codec_name -of csv=p=0 "$mkv_file" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}✗${NC} ffprobe failed to analyze subtitle streams: $temp_output"
        return 1
    fi
    
    # Check if we found any ASS/SSA subtitles
    if echo "$temp_output" | grep -q -E "ass|ssa"; then
        return 0
    else
        return 1
    fi
}

# Function to get subtitle stream info (index, codec, language)
get_subtitle_info() {
    local mkv_file="$1"
    local temp_output
    local exit_code
    
    # Get stream index, codec name, and language tag with error handling
    temp_output=$(ffprobe -v error -select_streams s -show_entries stream=index,codec_name:stream_tags=language -of json "$mkv_file" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}✗${NC} ffprobe failed to get subtitle stream info: $temp_output" >&2
        return 1
    fi
    
    # Validate that we got valid JSON output using jq
    if ! echo "$temp_output" | jq empty >/dev/null 2>&1; then
        echo -e "  ${RED}✗${NC} ffprobe returned invalid JSON output" >&2
        return 1
    fi
    
    echo "$temp_output"
    return 0
}

# Function to extract and convert ASS to SRT
extract_and_convert() {
    local mkv_file="$1"
    local base_name="${mkv_file%.*}"
    local subtitle_count=0
    local stream_info
    
    echo -e "${GREEN}Processing: $mkv_file${NC}"
    
    # Get subtitle stream information as JSON with error handling
    if ! stream_info=$(get_subtitle_info "$mkv_file"); then
        echo -e "  ${RED}✗${NC} Failed to get subtitle stream information"
        return 0
    fi
    
    # Check if we have any subtitle streams at all
    local stream_count=$(echo "$stream_info" | jq '.streams | length' 2>/dev/null)
    if [ -z "$stream_count" ] || [ "$stream_count" -eq 0 ]; then
        echo -e "  ${YELLOW}No subtitle streams found${NC}"
        return 0
    fi
    
    # Process each subtitle stream using jq
    local stream_index=0
    
    while [ $stream_index -lt "$stream_count" ]; do
        # Extract stream data using jq
        local codec_name=$(echo "$stream_info" | jq -r ".streams[$stream_index].codec_name // empty" 2>/dev/null)
        local language=$(echo "$stream_info" | jq -r ".streams[$stream_index].tags.language // empty" 2>/dev/null)
        local actual_index=$(echo "$stream_info" | jq -r ".streams[$stream_index].index // empty" 2>/dev/null)
        
        # Skip if we couldn't parse the stream data
        if [ -z "$codec_name" ]; then
            ((stream_index++))
            continue
        fi
        
        # Check if this is an ASS/SSA subtitle
        if [[ "$codec_name" == "ass" ]] || [[ "$codec_name" == "ssa" ]]; then
            # Determine output filename
            local output_suffix
            if [ -n "$language" ] && [ "$language" != "und" ] && [ "$language" != "null" ]; then
                # Use language code if available and not "undefined"
                output_suffix="$language"
                echo "  Extracting subtitle stream $actual_index (language: $language)..."
            else
                # Fall back to actual index if no language specified
                output_suffix="$actual_index"
                echo "  Extracting subtitle stream $actual_index (no language tag)..."
            fi
            
            local output_file="${base_name}.${output_suffix}.srt"
            
            # Handle duplicate language codes by appending index
            if [ -f "$output_file" ]; then
                output_file="${base_name}.${output_suffix}.${actual_index}.srt"
                echo "  Note: Multiple ${output_suffix} subtitles found, using index suffix"
            fi

            if [ -f "$output_file" ]; then
                echo -e "  ${YELLOW}!${NC} File '$output_file' already exists, skipping"
                ((stream_index++))
                continue
            fi
            
            # Check if output directory is writable
            local output_dir=$(dirname "$output_file")
            if [ ! -w "$output_dir" ]; then
                echo -e "  ${RED}✗${NC} Output directory is not writable: $output_dir"
                ((stream_index++))
                continue
            fi
            
            # Extract and convert ASS to SRT in one step using ffmpeg with proper error handling
            local ffmpeg_output
            local ffmpeg_exit_code
            
            # Run ffmpeg and capture both stdout and stderr
            # Use the absolute stream index from ffprobe, not subtitle stream index
            ffmpeg_output=$(ffmpeg -i "$mkv_file" -map 0:$actual_index -c:s srt "$output_file" -y -loglevel error 2>&1)
            ffmpeg_exit_code=$?
            
            if [ $ffmpeg_exit_code -eq 0 ]; then
                # Verify the output file was created and is not empty
                if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                    echo -e "  ${GREEN}✓${NC} Created: $output_file"
                    ((subtitle_count++))
                else
                    echo -e "  ${RED}✗${NC} ffmpeg reported success but output file is empty or missing"
                    # Clean up empty file if it exists
                    [ -f "$output_file" ] && rm -f "$output_file"
                fi
            else
                echo -e "  ${RED}✗${NC} ffmpeg failed to extract stream $actual_index (exit code: $ffmpeg_exit_code)"
                if [ -n "$ffmpeg_output" ]; then
                    echo -e "  ${RED}ffmpeg error:${NC} $ffmpeg_output"
                fi
                # Clean up partial file if it exists
                [ -f "$output_file" ] && rm -f "$output_file"
            fi
        fi
        
        ((stream_index++))
    done
    
    if [ $subtitle_count -eq 0 ]; then
        echo -e "  ${YELLOW}No ASS subtitles found or extraction failed${NC}"
    else
        echo -e "  ${GREEN}Extracted $subtitle_count subtitle(s)${NC}"
    fi
    
    return $subtitle_count
}

# Main script
main() {
    check_dependencies
    
    # Check if the input path exists
    if [ ! -e "$SEARCH_PATH" ]; then
        echo -e "${RED}Error: File or directory '$SEARCH_PATH' does not exist${NC}"
        exit 1
    fi
    
    # --- Logic to handle file or directory input ---
    if [ -f "$SEARCH_PATH" ]; then
        # --- Handle a single file ---
        local lower_case_path="${SEARCH_PATH,,}"
        if [[ "$lower_case_path" != *.mkv ]]; then
            echo -e "${RED}Error: Provided file is not an MKV file.${NC}"
            exit 1
        fi
        
        echo "================================================"
        if has_ass_subtitles "$SEARCH_PATH"; then
            extract_and_convert "$SEARCH_PATH"
        fi
        echo "================================================"
        echo -e "${GREEN}Done.${NC}"

    elif [ -d "$SEARCH_PATH" ]; then
        # --- Handle a directory ---
        if [ ! -r "$SEARCH_PATH" ]; then
            echo -e "${RED}Error: Directory '$SEARCH_PATH' is not readable${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Searching for MKV files with ASS subtitles in: $SEARCH_PATH${NC}"
        echo "================================================"
        
        local total_files=0
        local processed_files=0
        local total_subtitles=0
        local failed_files=0
        
        # Find all MKV files with error handling
        while IFS= read -r -d '' mkv_file; do
            ((total_files++))
            
            # Skip if file validation fails
            if ! validate_mkv_file "$mkv_file" >/dev/null 2>&1; then
                ((failed_files++))
                continue
            fi
            
            if has_ass_subtitles "$mkv_file"; then
                extract_and_convert "$mkv_file"
                local subtitles_extracted=$?
                if [ $subtitles_extracted -gt 0 ]; then
                    ((processed_files++))
                    ((total_subtitles+=subtitles_extracted))
                fi
                echo "------------------------------------------------"
            fi
        done < <(find "$SEARCH_PATH" -type f -iname "*.mkv" -print0 2>/dev/null)
        
        # Summary
        echo
        echo -e "${GREEN}Summary:${NC}"
        echo "Total MKV files found: $total_files"
        echo "Files with ASS subtitles: $processed_files"
        echo "Total subtitles extracted: $total_subtitles"
        if [ $failed_files -gt 0 ]; then
            echo -e "${YELLOW}Files that failed validation: $failed_files${NC}"
        fi
        
        if [ $total_files -eq 0 ]; then
            echo -e "${YELLOW}No MKV files found in the specified directory${NC}"
        fi
    else
      echo -e "${RED}Error: '$SEARCH_PATH' is not a regular file or directory.${NC}"
      exit 1
    fi
}

# Run the main function
main "$@"
