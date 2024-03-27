all: file_page_stat

pmparser.o: pmparser.h pmparser.c
	gcc -O -c pmparser.c -o $@

pagemap.o: pagemap.h pagemap.c
	gcc -O -c pagemap.c -o $@

main.o: file_page_stat.cpp
	g++ -O -c file_page_stat.cpp -o $@

file_page_stat: main.o pmparser.o pagemap.o
	g++ -O2  $^ -o file_page_stat

