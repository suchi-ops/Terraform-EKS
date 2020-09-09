FROM tomcat:8.5
MAINTAINER Demo Project <demo@gmail.com>

RUN apt-get update && \
	rm -rf /var/lib/apt/lists/* && apt-get clean && apt-get purge

COPY target/demo.war /usr/local/tomcat/webapps/demo.war

EXPOSE 8080
CMD ["catalina.sh", "run"]