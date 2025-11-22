require 'sinatra'
require 'fileutils'
require 'digest/blake3'
require 'sqlite3'

# for when you forget the curl command for to upload stuff, it's <<< curl -X POST -F "file=@/filepath/file.ext" 0.0.0.0:8080/upload >>>
# for downloads, its  curl -f -J -O http://0.0.0.0:8080/files/HASH >>>

#  setup
set :bind, '0.0.0.0'
set :port, 8080
ENV['TMPDIR'] = '/home/avery0/Documents/lanceolate/TMPDIR'

 FileUtils.mkdir_p ENV['TMPDIR']
# use home dir TMPDIR folder instead of /tmp so rack doesn't complain about running out of /tmp

FileUtils.mkdir_p '/home/avery0/Documents/lanceolate/storage'

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

get '/files/:hash' do

  hash = params[:hash]
  row = db.execute("SELECT * FROM lanceolate WHERE hash = ?", hash).first

  halt 404  if row.nil? || !File.exist?(row[0]) || File.zero?(row[0])

  path, original_filename = row[0], File.basename(row[0])

  attachment original_filename

  send_file path

end
