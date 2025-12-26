# Scientific Data Manuscript

This directory contains the manuscript for submission to Scientific Data (Nature Portfolio).

## Structure

- `main.tex`: Main manuscript LaTeX source
- `references.bib`: Bibliography
- `figures/`: Figures (to be added)
- `supplementary/`: Supplementary materials

## Building

```bash
cd paper
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

## Status

- [x] Basic structure created
- [ ] Abstract finalized
- [ ] Methods section completed
- [ ] Data Records section completed
- [ ] Technical Validation section completed
- [ ] Figures created
- [ ] Bibliography completed
- [ ] Final review

## Notes

- Follow Scientific Data Data Descriptor format
- Include all required sections per guidelines
- Ensure reproducibility statements are clear
- Include DOI once assigned from Zenodo

