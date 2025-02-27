# Build stage
FROM maven:3-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn clean package -DskipTests
RUN rm -rf /root/.m2 /app/src /app/pom.xml

# Production stage
FROM eclipse-temurin:17-jre-alpine AS production
WORKDIR /app
COPY --from=build /app/target/*.jar ./app.jar
EXPOSE 8080
ENTRYPOINT ["java","-XX:+UseSerialGC", "-XX:MaxRAMPercentage=50", "-jar", "app.jar"]
# "-XX:MaxRAMPercentage=50" - JVM default value is 25%
# "-XX:+UseSerialGC" for JDK 17+ default is G1GC, that consumes more memory than SerialGC