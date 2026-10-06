// Reads an Android App Bundle (.aab) without Java/bundletool.
// The bundle is a zip; base/manifest/AndroidManifest.xml inside it is aapt2
// proto-encoded. We walk the proto tree to read the root <manifest> attributes.

use serde::Serialize;
use std::collections::HashMap;
use std::io::Read;

#[derive(Serialize)]
pub struct AabInfo {
    pub application_id: String,
    pub version_code: Option<i64>,
    pub version_name: Option<String>,
}

pub fn inspect(path: &str) -> Result<AabInfo, String> {
    let file = std::fs::File::open(path).map_err(|e| format!("Ouverture impossible : {e}"))?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("AAB illisible (zip) : {e}"))?;
    let mut entry = zip
        .by_name("base/manifest/AndroidManifest.xml")
        .map_err(|_| "Manifeste introuvable dans l'AAB".to_string())?;
    let mut bytes = Vec::new();
    entry
        .read_to_end(&mut bytes)
        .map_err(|e| format!("Lecture du manifeste : {e}"))?;

    let attrs = root_attributes(&bytes)?;
    let application_id = attrs
        .get("package")
        .cloned()
        .filter(|s| !s.is_empty())
        .ok_or("Aucun applicationId trouvé dans le manifeste")?;
    let version_code = attrs.get("versionCode").and_then(|s| s.parse::<i64>().ok());
    let version_name = attrs.get("versionName").cloned();

    Ok(AabInfo { application_id, version_code, version_name })
}

// MARK: - minimal protobuf reader

enum FieldVal {
    Len(Vec<u8>),
    Varint(u64),
    Other,
}

fn read_varint(data: &[u8], pos: &mut usize) -> Option<u64> {
    let mut result: u64 = 0;
    let mut shift: u64 = 0;
    while *pos < data.len() {
        let b = data[*pos];
        *pos += 1;
        result |= ((b & 0x7f) as u64) << shift;
        if b & 0x80 == 0 {
            return Some(result);
        }
        shift += 7;
        if shift > 63 {
            return None;
        }
    }
    None
}

fn parse_fields(data: &[u8]) -> Vec<(u32, FieldVal)> {
    let mut pos = 0usize;
    let mut out = Vec::new();
    while let Some(key) = read_varint(data, &mut pos) {
        let field = (key >> 3) as u32;
        let wire = (key & 7) as u32;
        match wire {
            0 => match read_varint(data, &mut pos) {
                Some(v) => out.push((field, FieldVal::Varint(v))),
                None => break,
            },
            2 => {
                let len = match read_varint(data, &mut pos) {
                    Some(l) => l as usize,
                    None => break,
                };
                if pos + len > data.len() {
                    break;
                }
                out.push((field, FieldVal::Len(data[pos..pos + len].to_vec())));
                pos += len;
            }
            1 => {
                if pos + 8 > data.len() {
                    break;
                }
                pos += 8;
                out.push((field, FieldVal::Other));
            }
            5 => {
                if pos + 4 > data.len() {
                    break;
                }
                pos += 4;
                out.push((field, FieldVal::Other));
            }
            _ => break,
        }
    }
    out
}

fn string_field(fields: &[(u32, FieldVal)], num: u32) -> Option<String> {
    fields.iter().find_map(|(f, v)| match (f, v) {
        (f, FieldVal::Len(b)) if *f == num => Some(String::from_utf8_lossy(b).to_string()),
        _ => None,
    })
}

fn len_field(fields: &[(u32, FieldVal)], num: u32) -> Option<Vec<u8>> {
    fields.iter().find_map(|(f, v)| match (f, v) {
        (f, FieldVal::Len(b)) if *f == num => Some(b.clone()),
        _ => None,
    })
}

// XmlNode: element = 1 · XmlElement: attribute = 4 (repeated)
// XmlAttribute: name = 2, value = 3, compiled_item = 6
fn root_attributes(manifest: &[u8]) -> Result<HashMap<String, String>, String> {
    let top = parse_fields(manifest);
    let element = len_field(&top, 1).ok_or("Manifeste illisible (format inattendu)")?;
    let elem_fields = parse_fields(&element);

    let mut result = HashMap::new();
    for (f, v) in &elem_fields {
        if *f != 4 {
            continue;
        }
        let attr_bytes = match v {
            FieldVal::Len(b) => b,
            _ => continue,
        };
        let attr = parse_fields(attr_bytes);
        let name = match string_field(&attr, 2) {
            Some(n) if !n.is_empty() => n,
            _ => continue,
        };
        if let Some(value) = string_field(&attr, 3) {
            if !value.is_empty() {
                result.insert(name, value);
                continue;
            }
        }
        // versionCode etc. are stored as a compiled Item → Primitive int.
        if let Some(ci) = len_field(&attr, 6) {
            if let Some(iv) = primitive_int(&ci) {
                result.insert(name, iv.to_string());
            }
        }
    }
    Ok(result)
}

// Item.prim = 7 → Primitive.int_decimal_value = 6 / int_hexadecimal_value = 7
fn primitive_int(item_bytes: &[u8]) -> Option<i64> {
    let item = parse_fields(item_bytes);
    let prim = len_field(&item, 7)?;
    let pf = parse_fields(&prim);
    pf.iter().find_map(|(f, v)| match (f, v) {
        (f, FieldVal::Varint(x)) if *f == 6 || *f == 7 => Some(*x as i64),
        _ => None,
    })
}
