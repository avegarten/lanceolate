require 'sinatra'
require 'fileutils'
require 'digest/blake3'
require 'sqlite3'

 ENV['TMPDIR'] = '/home/averys/Documents/lanceolate/TMPDIR'
 FileUtils.mkdir_p ENV['TMPDIR']
# use home dir TMPDIR folder instead of /tmp so rack doesn't complain about running out of /tmp

FileUtils.mkdir_p '/home/averys/Documents/lanceolate/storage'

db = SQLite3::Database.open("data.db")
db.execute <<~SQL
  CREATE TABLE IF NOT EXISTS lanceolate(
      path TEXT PRIMARY KEY,
      hash TEXT NOT NULL,
      uploaded_time INTEGER NOT NULL,
      file_size INTEGER NOT NULL
                                       
  );
SQL

post '/upload' do

  stat = File.stat(params[:file][:tempfile])
  uploaded_time = stat.mtime.to_i
  file_size = stat.size.to_i

  filename = File.basename(params[:file][:filename])

  FileUtils.mv(params[:file][:tempfile].path, "storage/#{filename}")

  digest = Digest::Blake3.file("storage/#{filename}").hexdigest
  sharding = digest[0,2]
  # calculate hash from landing space

  FileUtils.mkdir_p "storage/#{sharding}/#{digest}"
  FileUtils.mv "storage/#{filename}", "storage/#{sharding}/#{digest}"
  final_path = "storage/#{sharding}/#{digest}/#{filename}"
  # make hash bashed sharding directory

  begin
  db.execute("INSERT INTO lanceolate (path, hash, uploaded_time, file_size) VALUES (?, ?, ?, ?)",
  [final_path, digest, uploaded_time, file_size])

rescue => e
  puts "DB ERROR: #{e.message}"
end

  # add to db, rescue for now

  "uploaded: #{filename} -> #{final_path}"
end

get '/download' do
  # stuff to download files add them later
  # db.execute
end