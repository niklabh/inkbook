#!/bin/bash

# Validation script for the ink! book project
# Checks that all required files are present and have content

echo "🔍 Validating 'Mastering ink!' book project..."

# Required files
REQUIRED_FILES=(
    "README.md"
    "preface.md"
    "chapter01.md"
    "chapter02.md"
    "chapter03.md"
    "chapter04.md"
    "chapter05.md"
    "chapter06.md"
    "chapter07.md"
    "chapter08.md"
    "chapter09.md"
    "chapter10.md"
    "appendix.md"
    "build.sh"
)

# Check if all files exist and have content
missing_files=()
empty_files=()

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    elif [ ! -s "$file" ]; then
        empty_files+=("$file")
    fi
done

# Report results
if [ ${#missing_files[@]} -eq 0 ] && [ ${#empty_files[@]} -eq 0 ]; then
    echo "✅ All files present and contain content"
    
    # Count total words across all chapters
    total_words=0
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ "$file" == *.md ]]; then
            words=$(wc -w < "$file" 2>/dev/null || echo 0)
            total_words=$((total_words + words))
        fi
    done
    
    echo "📊 Total word count: $(printf "%'d" $total_words) words"
    echo "📚 Estimated reading time: $((total_words / 250)) minutes"
    echo ""
    echo "🎯 Project Status: COMPLETE"
    echo ""
    echo "Next steps:"
    echo "1. Run ./build.sh to generate the complete book"
    echo "2. Review the generated mastering-ink-complete.md"
    echo "3. Share with the ink! community!"
    
else
    echo "❌ Issues found:"
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "Missing files:"
        printf '  - %s\n' "${missing_files[@]}"
    fi
    
    if [ ${#empty_files[@]} -gt 0 ]; then
        echo "Empty files:"
        printf '  - %s\n' "${empty_files[@]}"
    fi
    
    exit 1
fi
