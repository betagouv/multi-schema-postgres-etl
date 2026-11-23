FROM ruby:3.4.13-slim

# Add PostgreSQL repository for version 18
RUN apt-get update && apt-get install -y gnupg2 lsb-release wget ca-certificates \
&& wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg \
&& echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
# Install PostgreSQL 18 client and other dependencies
&& apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    postgresql-client-18 \
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
