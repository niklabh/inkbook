#!/bin/bash

# Build script for "Mastering ink!: Building Production-Ready Smart Contracts on Substrate"
# This script combines all chapters into a single markdown file

set -e

OUTPUT_FILE="mastering-ink-complete.md"
TEMP_FILE="temp_book.md"

echo "Building 'Mastering ink!' book..."

# Remove existing output file
if [ -f "$OUTPUT_FILE" ]; then
    rm "$OUTPUT_FILE"
fi

# Create title page
cat > "$TEMP_FILE" << 'EOF'
# Mastering ink!: Building Production-Ready Smart Contracts

**A Comprehensive Technical Guide**

*For developers who want to build sophisticated smart contracts using ink! on polkadot-sdk*

---

**Prerequisites:** Intermediate Rust proficiency and basic blockchain knowledge  
**Target Audience:** Rust developers, blockchain developers, smart contract architects  
**Publication Date:** 2024

---

EOF

# Add table of contents
cat >> "$TEMP_FILE" << 'EOF'
## Table of Contents

- **Preface**: Who This Book Is For
- **Chapter 1**: The ink! Paradigm: Rust on the Blockchain
- **Chapter 2**: Anatomy of an ink! Contract: Your First Build
- **Chapter 3**: Deep Dive into State: Managing Contract Storage
- **Chapter 4**: The Logic Layer: Messages and Constructors
- **Chapter 5**: Interoperability: Events and Cross-Contract Calls
- **Chapter 6**: Advanced ink! Patterns and Techniques
- **Chapter 7**: Bulletproof Your Logic: Comprehensive Contract Testing
- **Chapter 8**: Debugging and Optimization
- **Chapter 9**: From Localhost to Live: Deployment and Interaction
- **Chapter 10**: Capstone Project: Building a Decentralized Autonomous Organization (DAO)
- **Appendix**: Cheatsheets and Further Resources

---

EOF

# Function to add chapter with page break
add_chapter() {
    local file=$1
    local title=$2
    
    if [ -f "$file" ]; then
        echo "Adding $title..."
        echo "" >> "$TEMP_FILE"
        echo "---" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
        cat "$file" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
    else
        echo "Warning: $file not found, skipping $title"
    fi
}

# Add all chapters in order
add_chapter "preface.md" "Preface"
add_chapter "chapter01.md" "Chapter 1"
add_chapter "chapter02.md" "Chapter 2"
add_chapter "chapter03.md" "Chapter 3"
add_chapter "chapter04.md" "Chapter 4"
add_chapter "chapter05.md" "Chapter 5"
add_chapter "chapter06.md" "Chapter 6"
add_chapter "chapter07.md" "Chapter 7"
add_chapter "chapter08.md" "Chapter 8"
add_chapter "chapter09.md" "Chapter 9"
add_chapter "chapter10.md" "Chapter 10"
add_chapter "appendix.md" "Appendix"

# Add final footer
cat >> "$TEMP_FILE" << 'EOF'

---

## About This Book

This book was created to provide a comprehensive guide to ink! smart contract development on Substrate. It covers everything from basic concepts to advanced production patterns, including:

- Complete development environment setup
- Storage management and optimization
- Advanced design patterns and architectures
- Comprehensive testing strategies
- Security best practices
- Production deployment workflows
- A complete DAO implementation project

### Technical Specifications

- **ink! Version**: 6.x series
- **Rust Edition**: 2021
- **Primary Toolchain**: cargo-contract
- **Target Environment**: WebAssembly (WASM)
- **Blockchain Framework**: polkadot-sdk with pallet-contracts

### Contributing

This book is designed to be a living resource for the ink! community. For updates, corrections, or contributions, please refer to the project repository: https://github.com/niklabh/inkbook.

### License

This work is intended for educational purposes and represents best practices as of the publication date. Smart contract development involves financial risks, and readers should conduct thorough testing and security audits before deploying contracts in production environments.

---

*End of Book*

EOF

# Move temp file to final output
mv "$TEMP_FILE" "$OUTPUT_FILE"

# Generate statistics
TOTAL_LINES=$(wc -l < "$OUTPUT_FILE")
TOTAL_WORDS=$(wc -w < "$OUTPUT_FILE")
TOTAL_CHARS=$(wc -c < "$OUTPUT_FILE")

echo ""
echo "✅ Book compilation complete!"
echo ""
echo "📊 Statistics:"
echo "   File: $OUTPUT_FILE"
echo "   Lines: $(printf "%'d" $TOTAL_LINES)"
echo "   Words: $(printf "%'d" $TOTAL_WORDS)"
echo "   Characters: $(printf "%'d" $TOTAL_CHARS)"
echo "   Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""

# Check if pandoc is available for additional formats
if command -v pandoc &> /dev/null; then
    echo "📚 Generating additional formats..."
    
    # Generate PDF (requires LaTeX)
    if command -v pdflatex &> /dev/null; then
        echo "   Generating PDF..."
        pandoc "$OUTPUT_FILE" -o "mastering-ink-complete.pdf" \
            --pdf-engine=pdflatex \
            --variable geometry:margin=1in \
            --variable fontsize=11pt \
            --variable documentclass=book \
            --toc \
            2>/dev/null && echo "   ✅ PDF generated: mastering-ink-complete.pdf" || echo "   ❌ PDF generation failed"
    fi
    
    # Generate EPUB
    echo "   Generating EPUB..."
    pandoc "$OUTPUT_FILE" -o "mastering-ink-complete.epub" \
        --toc \
        --metadata title="Mastering ink! Building Production-Ready Smart Contracts" \
        --metadata author="Nikhil Ranjan" \
        2>/dev/null && echo "   ✅ EPUB generated: mastering-ink-complete.epub" || echo "   ❌ EPUB generation failed"
    
    # Generate HTML
    echo "   Generating HTML..."
    pandoc "$OUTPUT_FILE" -o "mastering-ink-complete.html" \
        --toc \
        --standalone \
        --css=style.css \
        --metadata title="Mastering ink!" \
        2>/dev/null && echo "   ✅ HTML generated: mastering-ink-complete.html" || echo "   ❌ HTML generation failed"
    
else
    echo ""
    echo "💡 Install pandoc to generate additional formats (PDF, EPUB, HTML):"
    echo "   macOS: brew install pandoc"
    echo "   Ubuntu: sudo apt-get install pandoc"
    echo "   For PDF: also install texlive-latex-base texlive-latex-recommended"
fi

echo ""
echo "🎉 Build complete! The comprehensive ink! guide is ready."
echo ""
echo "📖 To read the book:"
echo "   cat $OUTPUT_FILE"
echo "   # or open in your favorite markdown viewer"
echo ""
echo "🚀 Ready to start building production-ready smart contracts with ink!"
