# cython: language_level=3

from libc.stdio cimport fopen, fclose, fgets, feof, FILE
from libc.stdlib cimport strtod
from libc.string cimport strncmp, strchr, strlen
from cpython.dict cimport PyDict_New, PyDict_SetItem, PyDict_Contains
from cpython.unicode cimport PyUnicode_FromString

DEF MAX_LINE_LENGTH = 1024

cdef parse_string(const char* value_str, int length):
    # Remove quotes and return the string content
    if length >= 2 and value_str[0] == b'"' and value_str[length-1] == b'"':
        return PyUnicode_FromString(value_str + 1)[:length-2]
    return PyUnicode_FromString(value_str)

cdef parse_array(const char* value_str):
    # TODO Memorybuffer, array? idk
    cdef list result = []
    return result

cdef parse_value(const char* value_str):
    cdef int length = strlen(value_str)
    cdef char* trimmed = value_str
    
    # Trim leading whitespace
    while trimmed[0] == b' ' and length > 0:
        trimmed += 1
        length -= 1
    
    # Check for boolean
    if strncmp(trimmed, "true", 4) == 0:
        return True
    elif strncmp(trimmed, "false", 5) == 0:
        return False
    
    # Check for arrays
    if trimmed[0] == b'[':
        return parse_array(trimmed)
    
    # Check for numbers
    cdef char* endptr
    cdef double dval = strtod(trimmed, &endptr)
    if endptr != trimmed:
        # Check if it's actually a float
        if strchr(trimmed, b'.') != NULL or strchr(trimmed, b'e') != NULL or strchr(trimmed, b'E') != NULL:
            return dval
        return int(dval)
    
    # Handle strings
    return parse_string(trimmed, length)

cdef dict parse_toml_file(FILE* cfile):
    cdef:
        char[MAX_LINE_LENGTH] line
        dict current_section = PyDict_New()
        dict root = current_section
        char* key
        char* value
        char* equal_pos
        int key_len
        char* section_name
        dict section_dict
        char* closing_bracket
        int value_len
        char* dot_pos
        char* section_part
        dict parent_dict
        dict temp_dict
    
    while not feof(cfile):
        if fgets(line, MAX_LINE_LENGTH, cfile) == NULL:
            break
        
        # Skip comments and empty lines
        if line[0] == b'#' or line[0] == b'\n':
            continue
        
        # Handle sections [section]
        if line[0] == b'[':
            section_name = line + 1
            # Find closing bracket
            closing_bracket = strchr(section_name, b']')
            if closing_bracket != NULL:
                closing_bracket[0] = b'\0'
                
                # Handle nested sections [section.subsection]
                parent_dict = root
                section_part = section_name
                while True:
                    dot_pos = strchr(section_part, b'.')
                    if dot_pos != NULL:
                        dot_pos[0] = b'\0'
                        # Get or create parent section
                        if PyDict_Contains(parent_dict, PyUnicode_FromString(section_part)):
                            parent_dict = parent_dict[PyUnicode_FromString(section_part)]
                        else:
                            temp_dict = PyDict_New()
                            PyDict_SetItem(parent_dict, PyUnicode_FromString(section_part), temp_dict)
                            parent_dict = temp_dict
                        section_part = dot_pos + 1
                    else:
                        # Create final section
                        section_dict = PyDict_New()
                        PyDict_SetItem(parent_dict, PyUnicode_FromString(section_part), section_dict)
                        current_section = section_dict
                        break
            continue
        
        # Find key-value pairs
        equal_pos = strchr(line, b'=')
        if equal_pos != NULL:
            # Split into key and value
            equal_pos[0] = b'\0'
            key = line
            value = equal_pos + 1
            
            # Trim whitespace from key
            while key[0] == b' ':
                key += 1
            key_len = strlen(key)
            while key_len > 0 and key[key_len-1] == b' ':
                key[key_len-1] = b'\0'
                key_len -= 1
            
            # Remove trailing newline from value
            value_len = strlen(value)
            if value_len > 0 and value[value_len-1] == b'\n':
                value[value_len-1] = b'\0'
            
            # Parse and store
            PyDict_SetItem(
                current_section,
                PyUnicode_FromString(key),
                parse_value(value)
            )
    
    return root

def read_toml(str file_path):
    cdef:
        FILE* cfile
        dict result
    
    cfile = fopen(file_path.encode('utf-8'), "r")
    if cfile == NULL:
        raise FileNotFoundError(f"Could not open file: {file_path}")
    
    try:
        result = parse_toml_file(cfile)
    finally:
        fclose(cfile)
    
    return result
