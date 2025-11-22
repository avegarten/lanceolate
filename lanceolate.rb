require 'sinatra'
require 'fileutils'
require 'digest/blake3'
require 'sqlite3'
# for when you forget the curl command for to upload stuff, it's <<< curl -X POST -F "file=@/filepath/file.ext" 0.0.0.0:8080/upload >>>
# for downloads, its  <<< curl -f -J -O http://0.0.0.0:8080/files/HASH >>>
# for deleting a file, its <<< curl -X DELELTE http://0.0.0.0:8080/shard/hash >>>

#  INITIAL SETUP
set :bind, '0.0.0.0'
set :port, 8080
ENV['TMPDIR'] = '/home/avery0/Documents/lanceolate/TMPDIR'
# you probably want to change this for your own system

FileUtils.mkdir_p ENV['TMPDIR']
# use home dir TMPDIR folder instead of /tmp so rack doesn't complain about running out of /tmp

FileUtils.mkdir_p '/home/avery0/Documents/lanceolate/storage'
# you probably want to change this one too for your own system, but keep the "/storage" where you want your files.


db = SQLite3::Database.open("data.db")
db.execute <<~SQL
  CREATE TABLE IF NOT EXISTS lanceolate(
      path TEXT PRIMARY KEY,
      hash TEXT NOT NULL,
      uploaded_time INTEGER NOT NULL,
      file_size INTEGER NOT NULL
                                       
  );
SQL

db.execute "CREATE UNIQUE INDEX IF NOT EXISTS idx_hash ON lanceolate(hash);"

post '/upload' do

  tempfile = params[:file][:tempfile]
  original_name= File.basename(params[:file][:filename])
  # get the tempfile and original file name

  stat = File.stat(tempfile)
  uploaded_time = stat.mtime.to_i
  file_size = stat.size.to_i
  # get file metadata

  digest = Digest::Blake3.file(tempfile).hexdigest
  sharding = digest[0,2]
  # generate hash and sharding

  final_dir = "storage/#{sharding}/#{digest}"
  final_path = "#{final_dir}/#{original_name}"
  # get the final storage path and combine final_dir and final_path

  FileUtils.mkdir_p final_dir
  FileUtils.cp tempfile.path, final_path
  # make final_dir and copy to the final_path

  db.execute <<-SQL, [final_path, digest, uploaded_time, file_size]
  INSERT INTO lanceolate (path, hash, uploaded_time, file_size) 
  VALUES (?, ?, ?, ?)
  ON CONFLICT(hash) DO NOTHING
SQL
  # add to db and avoid duplicate files using the ON CONFLICT(hash)

  "done! uploaded: #{original_name} -> #{final_path} copy it back with this hash: #{digest}"
  # tells user the file is uploaded and it worked !
end



get '/files/:hash' do
  hash = params[:hash]
  row = db.execute("SELECT * FROM lanceolate WHERE hash = ?", hash).first
  # look up the file record from db based on the hash

  halt 404  if row.nil? || !File.exist?(row[0]) || File.zero?(row[0])
  # return with an 404 error is file: 1. doesnt exist in db. 2. doesnt exist at all. 3. or nothing.

  path, original_filename = row[0], File.basename(row[0])
  attachment original_filename
  # get file path from the db record and extract the original filename then send the file as an attachment (forces download with original_filename)

  send_file path
  # final send !
end


delete '/files/:shard/:hash' do

  sharding = params[:shard]
  hash = params[:hash]

  dir = "storage/#{sharding}/#{hash}"
  rows = db.execute("SELECT * FROM lanceolate WHERE hash = ?", hash)
  # look for the hash in the db
  halt 404, "sorry not found. :c" if rows.nil? || rows.empty?

  deleted_files = []

  rows.each do |row|
    full_path = row[0]

    if File.exist?(full_path)
      FileUtils.rm_f(full_path)
      deleted_files << File.basename(full_path)
    end
    # checks for file existence and deletes the file
    db.execute("DELETE FROM lanceolate WHERE hash = ?", hash)
    # delete from the db
  end

  if Dir.exist?(dir) && Dir.empty?(dir)
    FileUtils.rm_rf(dir)
  end
  # remove the leftover hash

  "done! deleted: #{deleted_files.join(', ')}"

end

