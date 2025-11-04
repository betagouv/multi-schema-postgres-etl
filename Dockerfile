FROM ruby:3.3.10-slim

# Add PostgreSQL repository for version 16
RUN apt-get update && apt-get install -y gnupg2 lsb-release wget \
&& wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
&& echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
# Install PostgreSQL 16 client and other dependencies
&& apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    postgresql-client-16 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Copy the rest of the application
COPY . .

# Install gems
RUN bundle install --jobs 4

# Set environment variables
ENV LANG=C.UTF-8

# Command to run
#CMD ["echo", "use -it to run the container"]
CMD ["bundle", "exec", "ruby", "main.rb"]
