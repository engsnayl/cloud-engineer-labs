# Interview-prep slides

Visual reference cards for the interview questions covered in this project.
Each `.pptx` covers one question from `Interview-Prep-Combined.md` (in the
parent repo's interview-prep collection) — typically 1-2 slides per question.

Used as flash-up sections in the Module 1-10 video series for cloud-engineer-labs.

## Format

- **1 slide**: concept comparison or single hero diagram
- **2 slides**: concept on slide 1, architecture/flow diagram on slide 2

## Index

| ID | Topic | Module | Slides |
|---|---|---|---|
| aws-003 | NACLs vs Security Groups | 1 (security module) | TBD |
| aws-014 | IGW vs NAT Gateway | 1 (vpc module) | 2 |

## Building

Slides are generated from JS files in `_build/` using `pptxgenjs`.
The `_build/` directory is intentionally gitignored — only the `.pptx`
outputs go in version control.

```bash
