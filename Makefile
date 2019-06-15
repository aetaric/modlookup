all: listener api
clean: 
	rm modlookup-listener modlookup-api
listener: 
	crystal build src/modlookup-listener.cr
api:
	crystal build src/modlookup-api.cr
install:
	cp modlookup-listener /usr/local/bin/modlookup-listener
	cp modlookup-api /usr/local/bin/modlookup-api
