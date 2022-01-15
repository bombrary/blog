#!/usr/bin/env perl
$latex = 'platex %O -halt-on-error -interaction=nonstopmode -file-line-error %S';
$pdflatex = 'pdflatex %O -halt-on-error -interaction=nonstopmode -file-line-error %S';
$lualatex = 'lualatex %O -halt-on-error -interaction=nonstopmode -file-line-error %S';
$xelatex = 'xelatex %O -halt-on-error -interaction=nonstopmode -file-line-error %S';
$dvipdf = 'dvipdfmx %O -o %D %S';
$dvips = 'dvips %O -z -f %S | convbkmk -u > %D';
$ps2pdf = 'ps2pdf %O %S %D';
$pdf_mode = 3;
$pdf_previewer    = "open -ga /Applications/Skim.app";
