# Discourse Daily Digest Plugin

A Discourse plugin that automatically generates daily digest posts by summarizing content from newsapi.org.

## Features

- Automated daily digest post creation
- Content summarization and organization

## Setup

Follow the [standard Discourse plugin installation steps](https://meta.discourse.org/t/install-plugins-in-discourse/19157):

```sh
cd /var/discourse
git clone https://github.com/MatthewssSmith1/discourse-daily-digest.git ./plugins/discourse-daily-digest
./launcher rebuild app
```

## Configuration

Set the following settings in the admin panel:

- `OpenAI API Key`: Get your API key from [OpenAI](https://platform.openai.com/docs/guides/get-started).
- `News API Key`: Get your API key from [newsapi.org](https://newsapi.org/).
- `Daily Digest Category`: Select the id of the category where daily digest posts will be created.

## License

MIT
