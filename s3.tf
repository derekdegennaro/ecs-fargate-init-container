resource "aws_s3_bucket" "content" {
  bucket        = "${var.project}-content-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project}-content"
    Project = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.content.id
  key          = "index.html"
  content_type = "text/html"

  content = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>ECS Init Container POC</title>
      <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 80px auto; text-align: center; }
        h1   { color: #1a73e8; }
        .badge { background: #34a853; color: white; padding: 8px 16px; border-radius: 4px; }
      </style>
    </head>
    <body>
      <h1>ECS Init Container POC</h1>
      <p><span class="badge">SUCCESS</span></p>
      <p>This page was downloaded from S3 by the <strong>init container</strong>
         and is now being served by <strong>nginx</strong>.</p>
      <p>The init container ran to completion before nginx started.</p>
    </body>
    </html>
  HTML
}
