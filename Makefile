all: prereqs shards config install
clean: 
	rm modlookup-listener modlookup-api
listener: 
	crystal build src/modlookup-listener.cr
api:
	crystal build src/modlookup-api.cr
systemd:
	cp init/modlookup-listener.service /etc/systemd/system/
	cp init/modlookup-api.service /etc/systemd/system/
	systemctl daemon-reload
config:
	cp config-example.yml /etc/modlookup.yml
	chmod 0700 /etc/modlookup.yml
	chown root: /etc/modlookup.yml
prereqs:
	apt install -y libyaml-dev libbson-dev libmongoc-dev
shards:
	shards install
install: listener api systemd 
	cp modlookup-listener /usr/local/bin/modlookup-listener
	cp modlookup-api /usr/local/bin/modlookup-api
