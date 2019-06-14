all: listener
clean: 
	rm modlookup-listener 
listener: 
	crystal build src/modlookup-listener.cr
install:
	cp modlookup-listener /usr/local/bin/modlookup-listener
