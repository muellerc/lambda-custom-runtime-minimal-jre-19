FROM --platform=linux/amd64 amazonlinux:2 AS packer

# Update the packages and install tar, Maven and Zip
RUN yum -y update \
    && yum install -y zip tar git

RUN curl -L -o openjdk-19-ea+5_linux-x64_bin.tar.gz https://download.java.net/java/early_access/jdk19/5/GPL/openjdk-19-ea+5_linux-x64_bin.tar.gz
RUN tar xvf openjdk-19-ea+5_linux-x64_bin.tar.gz

RUN curl -L -o apache-maven-3.8.4-bin.tar.gz https://dlcdn.apache.org/maven/maven-3/3.8.4/binaries/apache-maven-3.8.4-bin.tar.gz
RUN tar xvf apache-maven-3.8.4-bin.tar.gz

ENV JAVA_HOME=/jdk-19
ENV PATH=$PATH:$JAVA_HOME/bin

# should show something similar to:
# openjdk version "19-ea" 2022-09-20
# OpenJDK Runtime Environment (build 19-ea+5-210)
# OpenJDK 64-Bit Server VM (build 19-ea+5-210, mixed mode, sharing)

RUN java -version

ENV M2_HOME=/apache-maven-3.8.4
ENV PATH=$PATH:$M2_HOME/bin

# should show something similar to:
# Apache Maven 3.8.4 (9b656c72d54e5bacbed989b64718c159fe39b537)
# Maven home: /apache-maven-3.8.4
# Java version: 19-ea, vendor: Oracle Corporation, runtime: /jdk-19
# Default locale: en_US, platform encoding: UTF-8
# OS name: "linux", version: "5.10.76-linuxkit", arch: "amd64", family: "unix"
RUN mvn -v

# Copy the software folder to the image and build the function
COPY software software
WORKDIR /software/example-function
RUN mvn clean package


# Find JDK module dependencies dynamically from our uber jar
RUN jdeps \
    # dont worry about missing modules
    --ignore-missing-deps \
    # suppress any warnings printed to console
    -q \
    # java release version targeting
    --multi-release 19 \
    # output the dependencies at end of run
    --print-module-deps \
    # pipe the result of running jdeps on the function jar to file
    target/function.jar > jre-deps.info

# Create a slim Java 18 JRE which only contains the required modules to run this function
RUN jlink --verbose \
    --compress 2 \
    --strip-java-debug-attributes \
    --no-header-files \
    --no-man-pages \
    --output /jre-19-slim \
    --add-modules $(cat jre-deps.info)


# Use Javas Application Class Data Sharing feature to precompile JDK and our function.jar file
# it creates the file /jre-19-slim/lib/server/classes.jsa
RUN /jre-19-slim/bin/java -Xshare:dump -Xbootclasspath/a:/software/example-function/target/function.jar -version


# Package everything together into a custom runtime archive
WORKDIR /

COPY bootstrap bootstrap
RUN chmod 755 bootstrap
RUN cp /software/example-function/target/function.jar function.jar
RUN zip -r runtime.zip \
    bootstrap \
    function.jar \
    /jre-19-slim
